//
//  ProcessCacheTests.swift
//  DependenceTests
//
//  Pins down the process-wide cache and the first-call-wins latch backing
//  ``prepareDependencies(_:)`` and ``Scene.dependencies(_:)``. These APIs
//  are startup primitives, not reload primitives, and that asymmetry is
//  itself a contract — the matrix in `Lifetime.md` depends on it.
//

@_spi(TestSupport) import Dependence
import DependenceTesting
import Foundation
import Testing

@testable import Dependence

// The no-op `.dependencies` trait is load-bearing: constructing it installs
// `DependenceTesting`'s Swift Testing issue-routing handler. Under the
// SwiftBuild backend each test target runs as its own bundle, so this bundle
// cannot rely on another target having installed the handler — without it,
// `withKnownIssue` blocks below would never see the `reportIssue` calls.
extension ProcessGlobalStateSuites {
    @Suite("Process-wide cache and prepare-state", .dependencies { _ in })
    struct ProcessCacheTests {
        private struct Switchable: Sendable, Equatable { var value: String }

        private enum SwitchableKey: DependencyKey {
            static var liveValue: Switchable { Switchable(value: "live") }
            static var testValue: Switchable { Switchable(value: "test") }
        }

        private func resetRuntime() {
            DependencyRuntimeState.resetForTesting()
        }

        @Test("prepareDependencies first call seeds the cache for subsequent reads")
        func firstCallSeedsCache() {
            resetRuntime()
            defer { resetRuntime() }

            prepareDependencies {
                $0[SwitchableKey.self] = Switchable(value: "prepared")
            }

            // Direct read on a fresh DependencyValues falls into resolve(), which
            // hits the cache populated by `installInitial`.
            #expect(DependencyValues()[SwitchableKey.self] == Switchable(value: "prepared"))
            #expect(DependencyValues.current[SwitchableKey.self] == Switchable(value: "prepared"))
        }

        @Test("Second prepareDependencies call reports an issue and is ignored")
        func secondCallReportsIssue() {
            resetRuntime()
            defer { resetRuntime() }

            prepareDependencies {
                $0[SwitchableKey.self] = Switchable(value: "first")
            }

            // The second call routes through `reportIssue` — Swift Testing's
            // issue handler records that as a test failure unless we declare it
            // expected via `withKnownIssue`.
            withKnownIssue("second prepareDependencies call must report") {
                prepareDependencies {
                    $0[SwitchableKey.self] = Switchable(value: "second-ignored")
                }
            }

            // The cache still holds the value installed by the first call.
            #expect(DependencyValues()[SwitchableKey.self] == Switchable(value: "first"))
        }

        @Test("Cached value resists later default re-resolution")
        func cacheValueStickyAcrossReads() {
            resetRuntime()
            defer { resetRuntime() }

            prepareDependencies {
                $0[SwitchableKey.self] = Switchable(value: "sticky")
            }

            for _ in 0..<8 {
                #expect(DependencyValues()[SwitchableKey.self] == Switchable(value: "sticky"))
            }
        }

        @Test("withDependencies still wins inside its scope, then cache value reappears")
        func withDependenciesShadowsButDoesNotEvictCache() {
            resetRuntime()
            defer { resetRuntime() }

            prepareDependencies {
                $0[SwitchableKey.self] = Switchable(value: "base")
            }

            withDependencies {
                $0[SwitchableKey.self] = Switchable(value: "scoped")
            } operation: {
                #expect(DependencyValues.current[SwitchableKey.self] == Switchable(value: "scoped"))
            }

            // The scoped override is task-local; leaving the operation restores
            // the cached prepared value, not the test default.
            #expect(DependencyValues.current[SwitchableKey.self] == Switchable(value: "base"))
        }

        @Test("Scene-style installIfNeeded is a silent first-call-wins no-op afterwards")
        func sceneStyleInstallIfNeededIsSilent() {
            resetRuntime()
            defer { resetRuntime() }

            var first = DependencyValues()
            first[SwitchableKey.self] = Switchable(value: "scene-first")
            PrepareDependenciesState.shared.installIfNeeded(first)

            // Repeated installIfNeeded with a different bag must NOT report and
            // must NOT replace the cached value.
            var second = DependencyValues()
            second[SwitchableKey.self] = Switchable(value: "scene-second")
            PrepareDependenciesState.shared.installIfNeeded(second)

            #expect(DependencyValues()[SwitchableKey.self] == Switchable(value: "scene-first"))
        }
    }
}
