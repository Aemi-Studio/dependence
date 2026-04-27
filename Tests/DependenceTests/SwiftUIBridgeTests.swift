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

@Suite("SwiftUI subtree override reaches non-View hosts", .serialized)
struct SwiftUIBridgeTests {

    private struct Greeter: Sendable, Equatable {
        var name: String
    }

    private enum GreeterKey: DependencyKey {
        static var liveValue: Greeter { Greeter(name: "live") }
        static var testValue: Greeter { Greeter(name: "test") }
    }

    /// Simulates what `View.dependencies(_:)` writes onto the subtree stack.
    /// We don't render SwiftUI here — that requires a host runloop — but
    /// the stack push is the same operation, and the resolution path is
    /// the one this test cares about.
    @discardableResult
    private func publishSubtreeOverride(_ mutate: (inout DependencyValues) -> Void) -> UUID {
        var copy = DependencyValues._current
        mutate(&copy)
        let id = UUID()
        DependencyValues._subtreeStack.withLock { stack in
            stack.append(.init(id: id, values: copy))
        }
        return id
    }

    private func clearSubtreeOverride() {
        DependencyValues._subtreeStack.withLock { $0.removeAll() }
    }

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
        let id = UUID()
        DependencyValues._subtreeStack.withLock { stack in
            stack.append(.init(id: id, values: .init()))
        }

        withDependencies {
            $0[GreeterKey.self] = Greeter(name: "task-local")
        } operation: {
            @Dependency(test: GreeterKey.self) var greeter
            #expect(greeter == Greeter(name: "task-local"))
        }
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
}

#endif
