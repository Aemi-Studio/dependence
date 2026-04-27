//
//  EnvironmentBridge.swift
//  Dependence
//
//  Two-way bridge between `DependencyValues` and SwiftUI's
//  `EnvironmentValues`. The container itself becomes an `EnvironmentKey`
//  value, so `.dependencies { … }` modifiers compose with SwiftUI's normal
//  invalidation tree.
//

#if canImport(SwiftUI)
import SwiftUI

extension EnvironmentValues {
    /// The active dependency container, available to any view in the tree.
    ///
    /// Override at any subtree boundary with ``SwiftUICore/View/dependencies(_:)``.
    @Entry public var dependencies: DependencyValues = .init()
}

extension View {
    /// Override dependencies for this view and its descendants — *subtree*
    /// scope.
    ///
    /// ```swift
    /// ContentView()
    ///     .dependencies { $0.apiClient = .preview }
    /// ```
    ///
    /// Use this for previews, A/B-style branches, and tests. For the *whole
    /// app's* dependencies, write the modifier on the `Scene` instead — that
    /// is the composition root and feeds `prepareDependencies(_:)`.
    ///
    /// SwiftUI invalidation respects the override — descendants reading via
    /// `@Dependency(\.apiClient)` are re-rendered when the override changes.
    /// `@Observable` view models and other non-View hosts also see the
    /// override through the process-wide subtree cell.
    public func dependencies(
        _ mutate: @escaping (inout DependencyValues) -> Void
    ) -> some View {
        modifier(DependenciesModifier(mutate: mutate))
    }
}

extension Scene {
    /// Configure the *app-wide* dependencies — composition-root scope.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup { HomeView() }
    ///             .dependencies {
    ///                 $0.authClient = .live
    ///                 $0.feedClient = .live
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// The first body evaluation seeds the process-wide cache via
    /// ``prepareDependencies(_:)`` so every `@Dependency` read — including
    /// ones in `@Observable` view models, off-MainActor actors, etc. — sees
    /// the same values without anyone having to import `Dependence` to do the
    /// installation by hand. Subsequent body evaluations are silent no-ops.
    ///
    /// Use this for the global "wire my live services" case. Use
    /// ``SwiftUICore/View/dependencies(_:)`` for *subtree* overrides
    /// (previews, A/B, tests).
    public func dependencies(
        _ mutate: @escaping (inout DependencyValues) -> Void
    ) -> some Scene {
        var copy = DependencyValues._current
        mutate(&copy)
        // Idempotent install — Scene.body re-evaluates on input changes; the
        // first call wins, the rest are silent.
        PrepareDependenciesState.shared.installIfNeeded(copy)
        return environment(\.dependencies, copy)
    }
}

/// Lifetime token for one `.dependencies(_:)` subtree.
///
/// `DependenciesModifier` owns one of these via `@StateObject`, so the
/// instance lives exactly as long as the modifier is part of the View
/// identity. When the subtree is removed (sheet dismissed, navigation pop,
/// branch swap), SwiftUI releases the `StateObject`, the registration
/// deallocates, and `deinit` removes its entry from the global stack.
@MainActor
private final class SubtreeRegistration: ObservableObject {
    let id = UUID()

    deinit {
        // We're already on `MainActor` here (the class is `@MainActor`-bound)
        // and the underlying `Locked` is `Sendable`, so the removal can run
        // synchronously without re-dispatching.
        let id = self.id
        DependencyValues._subtreeStack.withLock { stack in
            stack.removeAll { $0.id == id }
        }
    }
}

private struct DependenciesModifier: ViewModifier {
    let mutate: (inout DependencyValues) -> Void

    @Environment(\.dependencies) private var current
    @StateObject private var registration = SubtreeRegistration()

    func body(content: Content) -> some View {
        var copy = current
        mutate(&copy)
        // Upsert this modifier's entry on the subtree stack so non-View
        // hosts (e.g. `@Observable` view models) can resolve through it
        // when no `withDependencies` block is in scope.
        let id = registration.id
        DependencyValues._subtreeStack.withLock { stack in
            if let index = stack.firstIndex(where: { $0.id == id }) {
                stack[index].values = copy
            } else {
                stack.append(.init(id: id, values: copy))
            }
        }
        return content.environment(\.dependencies, copy)
    }
}
#endif
