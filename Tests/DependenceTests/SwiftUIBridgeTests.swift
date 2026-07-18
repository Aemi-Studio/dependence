//
//  SwiftUIBridgeTests.swift
//  DependenceTests
//
//  Covers the SwiftUI <-> DependencyValues bridge: the subtree-override cell
//  populated by `View.dependencies(_:)`, and the idempotent composition-root
//  install used by `Scene.dependencies(_:)`. Both must reach `@Dependency`
//  reads on non-View hosts (the case where SwiftUI never drives
//  `DynamicProperty.update()`), which is the main reason these paths exist.
//

#if canImport(SwiftUI)
    @testable import Dependence
    import DependenceTesting
    import Foundation
    import Testing
    import SwiftUI
    #if canImport(AppKit)
        import AppKit
    #endif
    #if canImport(UIKit) && !os(watchOS)
        import UIKit
    #endif

    // Nested under ProcessGlobalStateSuites: these tests publish and clear
    // process-wide subtree entries, and other suites' resetForTesting calls
    // would wipe them mid-test if the suites interleaved (sibling-level
    // .serialized does not serialize ACROSS suites — see the umbrella file).
    extension ProcessGlobalStateSuites {
        @Suite("SwiftUI subtree override reaches non-View hosts")
        struct SwiftUIBridgeTests {
            private struct Greeter: Sendable, Equatable {
                var name: String
            }

            private enum GreeterKey: DependencyKey {
                static var liveValue: Greeter { Greeter(name: "live") }
                static var testValue: Greeter { Greeter(name: "test") }
            }

            private enum SecondKey: DependencyKey {
                static var liveValue: Greeter { Greeter(name: "live-second") }
                static var testValue: Greeter { Greeter(name: "test-second") }
            }

            /// Simulates what `View.dependencies(_:)` writes onto the subtree stack.
            ///
            /// We don't render SwiftUI here — that requires a host runloop — but
            /// the publish is the same operation, and the resolution path is the
            /// one this test cares about.
            @discardableResult
            private func publishSubtreeOverride(_ mutate: (inout DependencyValues) -> Void) -> UUID {
                var copy = DependencyValues._current
                mutate(&copy)
                let id = UUID()
                DependencyValues._publishSubtree(id: id, values: copy)
                return id
            }

            private func clearSubtreeOverride() {
                DependencyValues._clearSubtreesForTesting()
            }

            // MARK: - Shared SwiftUI mount fixtures (AppKit + UIKit)

            @MainActor
            private final class MountedProbeRecorder {
                var values: [String] = []

                func record(_ value: String) {
                    values.append(value)
                }

                func clear() {
                    values.removeAll()
                }
            }

            @MainActor
            private struct MountedDependencyProbe: View {
                @Dependency(test: GreeterKey.self) private var greeter

                let recorder: MountedProbeRecorder

                var body: some View {
                    let name = greeter.name
                    let _ = recorder.record(name)
                    Text(name)
                }
            }

            #if canImport(AppKit)
                @MainActor
                private func render(_ host: NSHostingView<AnyView>) async {
                    host.frame = NSRect(x: 0, y: 0, width: 240, height: 120)
                    host.needsLayout = true
                    host.layoutSubtreeIfNeeded()
                    _ = host.fittingSize
                    await Task.yield()
                }

                @MainActor
                private func mountedProbe(
                    recorder: MountedProbeRecorder,
                    name: String
                ) -> AnyView {
                    AnyView(
                        MountedDependencyProbe(recorder: recorder)
                            .dependencies {
                                $0[GreeterKey.self] = Greeter(name: name)
                            }
                    )
                }

                @MainActor
                private struct SiblingsRoot: View {
                    let recorder: MountedProbeRecorder

                    var body: some View {
                        HStack {
                            MountedDependencyProbe(recorder: recorder)
                                .dependencies { $0[GreeterKey.self] = Greeter(name: "sibling-A") }
                            MountedDependencyProbe(recorder: recorder)
                                .dependencies { $0[GreeterKey.self] = Greeter(name: "sibling-B") }
                        }
                    }
                }
            #endif

            @Test("@Dependency on a non-View host resolves through the subtree cell")
            func subtreeOverrideReachesNonViewHost() {
                defer { clearSubtreeOverride() }
                publishSubtreeOverride {
                    $0[GreeterKey.self] = Greeter(name: "subtree")
                }
                // Reading via `@Dependency` should pick up the cell ahead of the
                // TaskLocal `_current` binding (which has nothing for this key).
                @Dependency(test: GreeterKey.self) var greeter
                #expect(greeter == Greeter(name: "subtree"))
            }

            @Test("Empty subtree-override container falls through to TaskLocal")
            func emptySubtreeFallsThrough() {
                defer { clearSubtreeOverride() }
                // Publish an *empty* container — the resolver must not pin "subtree
                // is in effect" off an empty bag.
                DependencyValues._publishSubtree(id: UUID(), values: .init())

                withDependencies {
                    $0[GreeterKey.self] = Greeter(name: "task-local")
                } operation: {
                    @Dependency(test: GreeterKey.self) var greeter
                    #expect(greeter == Greeter(name: "task-local"))
                }
            }

            @Test("withDependencies layers over an active subtree, preserving unrelated keys (F6)")
            func withDependenciesLayersOverSubtree() {
                defer { clearSubtreeOverride() }
                publishSubtreeOverride {
                    $0[GreeterKey.self] = Greeter(name: "subtree")
                    $0[SecondKey.self] = Greeter(name: "subtree-second")
                }
                withDependencies {
                    // Touch only SecondKey; GreeterKey must keep the subtree's
                    // value inside the block. (Pre-F6, the block seeded from the
                    // raw task-local and GreeterKey silently fell back to the
                    // context default "test".)
                    $0[SecondKey.self] = Greeter(name: "scoped-second")
                } operation: {
                    #expect(DependencyValues.current[GreeterKey.self] == Greeter(name: "subtree"))
                    #expect(DependencyValues.current[SecondKey.self] == Greeter(name: "scoped-second"))
                }
                // Outside the block the subtree fallback is intact.
                #expect(DependencyValues.current[SecondKey.self] == Greeter(name: "subtree-second"))
            }

            @Test("withDependencies overrides win against an active subtree")
            func taskLocalBeatsSubtree() {
                // Regression for the leak that caused `swift test` flakiness:
                // `_subtreeOverride` used to win over the TaskLocal `_current`,
                // so a leftover subtree from a parallel test could override values
                // that the current test had set via `withDependencies`. The new
                // precedence makes `withDependencies` always win.
                defer { clearSubtreeOverride() }
                publishSubtreeOverride {
                    $0[GreeterKey.self] = Greeter(name: "subtree")
                }
                withDependencies {
                    $0[GreeterKey.self] = Greeter(name: "task-local")
                } operation: {
                    @Dependency(test: GreeterKey.self) var greeter
                    #expect(greeter == Greeter(name: "task-local"))
                }
            }

            @Test("DependencyValues.current honors the subtree override")
            func currentAccessorHonorsSubtree() {
                // The public `current` accessor is what service-witness closures use
                // when they read inner deps without declaring their own `@Dependency`
                // (e.g. `func deps() -> DependencyValues { .current }`). It must
                // mirror the resolver chain — otherwise a SwiftUI subtree override
                // wins for the *outer* service but is invisible to the inner reads
                // its `liveValue` makes, producing the surprising "live service
                // calling preview client" outcome.
                defer { clearSubtreeOverride() }
                publishSubtreeOverride {
                    $0[GreeterKey.self] = Greeter(name: "subtree")
                }
                let snapshot = DependencyValues.current
                #expect(snapshot[GreeterKey.self] == Greeter(name: "subtree"))
            }

            @Test("captureDependencies snapshots the active subtree fallback for offloaded work")
            func captureSnapshotsSubtreeFallback() async {
                defer { clearSubtreeOverride() }
                publishSubtreeOverride {
                    $0[GreeterKey.self] = Greeter(name: "subtree")
                }
                let continuation = captureDependencies()
                clearSubtreeOverride()

                let observed = await Task.detached {
                    continuation.yield {
                        DependencyValues.current[GreeterKey.self].name
                    }
                }.value

                #expect(observed == "subtree")
            }

            @Test("Removing the active subtree falls back to context defaults")
            func removedSubtreeFallsBackToDefault() {
                let id = publishSubtreeOverride {
                    $0[GreeterKey.self] = Greeter(name: "subtree")
                }
                DependencyValues._removeSubtree(id: id)

                #expect(DependencyValues.current[GreeterKey.self] == Greeter(name: "test"))
            }

            #if canImport(AppKit)
                @MainActor
                @Test("Mounted SwiftUI views refresh the @Dependency environment snapshot")
                func mountedSwiftUIViewRefreshesEnvironmentSnapshot() async {
                    defer { clearSubtreeOverride() }
                    let recorder = MountedProbeRecorder()
                    let host = NSHostingView(rootView: mountedProbe(recorder: recorder, name: "first"))

                    await render(host)
                    #expect(recorder.values.contains("first"))

                    recorder.clear()
                    host.rootView = mountedProbe(recorder: recorder, name: "second")
                    await render(host)

                    #expect(recorder.values.contains("second"))
                    #expect(!recorder.values.contains("first"))
                }

                @MainActor
                @Test("Sibling subtrees deliver isolated values to View reads (G14)")
                func siblingViewsReadIndependentOverrides() async {
                    clearSubtreeOverride()
                    defer { clearSubtreeOverride() }

                    let recorder = MountedProbeRecorder()
                    let host = NSHostingView(rootView: AnyView(SiblingsRoot(recorder: recorder)))
                    await render(host)

                    // Each branch's `@Dependency` resolves through its own SwiftUI
                    // environment snapshot, so neither branch leaks into the other.
                    #expect(recorder.values.contains("sibling-A"))
                    #expect(recorder.values.contains("sibling-B"))
                }

                @Test("Non-View hosts see the last published sibling on the subtree stack (G14)")
                func nonViewHostReadsLastPublishedSibling() {
                    // Direct stack manipulation rather than a mounted SwiftUI tree:
                    // the contract under test is the resolver chain
                    // (`DependencyValues.current` picks the top entry of the stack),
                    // not SwiftUI's body-evaluation order. The mounted view tests
                    // above already verify SwiftUI publishes onto the stack.
                    clearSubtreeOverride()
                    defer { clearSubtreeOverride() }

                    var aBag = DependencyValues()
                    aBag[GreeterKey.self] = Greeter(name: "A")
                    var bBag = DependencyValues()
                    bBag[GreeterKey.self] = Greeter(name: "B")

                    let aID = UUID()
                    let bID = UUID()
                    DependencyValues._publishSubtree(id: aID, values: aBag)
                    DependencyValues._publishSubtree(id: bID, values: bBag)

                    // Last-writer-wins: B is the more recently pushed sibling.
                    #expect(DependencyValues.current[GreeterKey.self] == Greeter(name: "B"))

                    // Removing the top entry falls back to the earlier sibling.
                    DependencyValues._removeSubtree(id: bID)
                    #expect(DependencyValues.current[GreeterKey.self] == Greeter(name: "A"))
                }

                @Test("withDependencies wins over an active sibling subtree fallback (G14)")
                func taskLocalBeatsSiblingFallback() {
                    clearSubtreeOverride()
                    defer { clearSubtreeOverride() }

                    var bag = DependencyValues()
                    bag[GreeterKey.self] = Greeter(name: "subtree")
                    DependencyValues._publishSubtree(id: UUID(), values: bag)

                    let observed = withDependencies {
                        $0[GreeterKey.self] = Greeter(name: "task-local")
                    } operation: {
                        DependencyValues.current[GreeterKey.self]
                    }
                    #expect(observed == Greeter(name: "task-local"))
                }

                @MainActor
                @Test("Mounted SwiftUI subtree removal cleans up the process fallback")
                func mountedSwiftUISubtreeRemovalCleansFallback() async {
                    clearSubtreeOverride()
                    let host = NSHostingView(rootView: mountedProbe(recorder: MountedProbeRecorder(), name: "mounted"))

                    await render(host)
                    #expect(DependencyValues._subtreeStack.withLock { !$0.isEmpty })

                    host.rootView = AnyView(Text("removed"))
                    await render(host)
                    await Task.yield()

                    #expect(DependencyValues._subtreeStack.withLock { $0.isEmpty })
                }
            #endif

            // MARK: - UIKit-mounted SwiftUI

            #if canImport(UIKit) && !os(watchOS)
                @MainActor
                private func renderUIKit(_ host: UIHostingController<AnyView>) async {
                    host.view.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    await Task.yield()
                }

                @MainActor
                private func mountedProbeUI(
                    recorder: MountedProbeRecorder,
                    name: String
                ) -> AnyView {
                    AnyView(
                        MountedDependencyProbe(recorder: recorder)
                            .dependencies {
                                $0[GreeterKey.self] = Greeter(name: name)
                            }
                    )
                }

                @MainActor
                @Test("UIHostingController: SwiftUI environment refreshes on root replacement")
                func uiHostingRefreshesEnvironmentSnapshot() async {
                    clearSubtreeOverride()
                    defer { clearSubtreeOverride() }
                    let recorder = MountedProbeRecorder()
                    let host = UIHostingController(rootView: mountedProbeUI(recorder: recorder, name: "ui-first"))

                    await renderUIKit(host)
                    #expect(recorder.values.contains("ui-first"))

                    recorder.clear()
                    host.rootView = mountedProbeUI(recorder: recorder, name: "ui-second")
                    await renderUIKit(host)

                    #expect(recorder.values.contains("ui-second"))
                    #expect(!recorder.values.contains("ui-first"))
                }

                @MainActor
                @Test("UIHostingController: subtree removal cleans the process fallback")
                func uiHostingSubtreeRemovalCleansFallback() async {
                    clearSubtreeOverride()
                    let host = UIHostingController(
                        rootView: mountedProbeUI(recorder: MountedProbeRecorder(), name: "ui-mounted")
                    )

                    await renderUIKit(host)
                    #expect(DependencyValues._subtreeStack.withLock { !$0.isEmpty })

                    host.rootView = AnyView(Text("removed"))
                    await renderUIKit(host)
                    await Task.yield()

                    #expect(DependencyValues._subtreeStack.withLock { $0.isEmpty })
                }
            #endif
        }
    }

#endif
