//
//  WithDependencies.swift
//  Dependence
//
//  Scoped override APIs. Mirrors `TaskLocal.withValue` but on the
//  DependencyValues struct itself.
//

import Foundation

// MARK: - Sync overrides

/// Apply overrides for the duration of `operation`.
///
/// ```swift
/// withDependencies {
///     $0.apiClient = .mock
///     $0.uuid = .incrementing
/// } operation: {
///     // …code that reads `@Dependency(\.apiClient)` sees the mock here.
/// }
/// ```
///
/// The mutation is applied to a copy of the **active** container — the same
/// one ``DependencyValues/current`` resolves — so overrides *layer*: a
/// `withDependencies` block nested inside a SwiftUI `.dependencies { … }`
/// subtree keeps the subtree's unrelated keys and only replaces the ones it
/// mutates. (Earlier releases seeded from the raw task-local instead, which
/// silently dropped an enclosing subtree's other keys to context defaults.)
///
/// Overrides propagate to child structured tasks (`async let`, `withTaskGroup`'s
/// `addTask`) automatically because they ride on `@TaskLocal`.
/// `Task.detached` and unstructured callbacks (Combine, GCD,
/// `NotificationCenter`) do **not** inherit; use ``captureDependencies()``
/// to snapshot and rebind across those boundaries.
@discardableResult
public func withDependencies<R>(
    _ mutate: (inout DependencyValues) throws -> Void,
    operation: () throws -> R
) rethrows -> R {
    // Seed from the resolved active container (task-local, else subtree
    // fallback) rather than the raw `_current` task-local, so nesting inside
    // a SwiftUI subtree composes instead of resetting unrelated keys.
    var copy = DependencyValues.resolveActive(environmentSnapshot: nil)
    try mutate(&copy)
    return try DependencyValues.$_current.withValue(copy, operation: operation)
}

// MARK: - Async overrides

/// Async form of ``withDependencies(_:operation:)-9aaby``.
///
/// Inherits the caller's actor isolation via `#isolation` so overrides set
/// on `@MainActor` propagate without forcing a hop. Seeds from the resolved
/// active container like the synchronous form — see its documentation for
/// the layered-composition semantics.
@discardableResult
public func withDependencies<R: Sendable>(
    _ mutate: (inout DependencyValues) throws -> Void,
    isolation: isolated (any Actor)? = #isolation,
    operation: () async throws -> R
) async rethrows -> R {
    var copy = DependencyValues.resolveActive(environmentSnapshot: nil)
    try mutate(&copy)
    return try await DependencyValues.$_current.withValue(copy, operation: operation)
}

// MARK: - Snapshot-at-construction helpers

extension DependencyValues {
    /// Capture the active dependency container (task-local override, latest
    /// SwiftUI subtree fallback, or empty container) into a `Sendable`
    /// snapshot.
    ///
    /// Use this from the call site that constructs a long-lived non-`View`
    /// host (an `@Observable` view model, an actor, a service) to
    /// deterministically pin its dependency reads to "the values that were
    /// active when the host was made", regardless of which sibling subtree
    /// publishes next.
    ///
    /// ```swift
    /// @State private var model = withDependencies({
    ///     $0 = DependencyValues.snapshot()
    /// }) {
    ///     GreetingViewModel()
    /// }
    /// ```
    public static func snapshot() -> DependencyValues {
        DependencyValues.current
    }
}

/// Bind a previously-captured `DependencyValues` snapshot for the duration
/// of `operation`.
///
/// This is the recommended pattern for constructing long-lived non-`View`
/// hosts under a stable dependency scope:
///
/// ```swift
/// // Inside a SwiftUI body or onAppear:
/// @Environment(\.dependencies) private var ambient
///
/// @State private var model: GreetingViewModel?
///
/// func makeModel() {
///     model = withSnapshotDependencies(ambient) {
///         GreetingViewModel()
///     }
/// }
/// ```
///
/// The model's `@Dependency` reads then resolve through the task-local
/// layer, which always wins over the process-wide subtree fallback. The
/// model becomes deterministic across sibling subtree publication.
@discardableResult
public func withSnapshotDependencies<R>(
    _ snapshot: DependencyValues,
    operation: () throws -> R
) rethrows -> R {
    try DependencyValues.$_current.withValue(snapshot, operation: operation)
}

/// Async form of ``withSnapshotDependencies(_:operation:)``.
@discardableResult
public func withSnapshotDependencies<R: Sendable>(
    _ snapshot: DependencyValues,
    isolation: isolated (any Actor)? = #isolation,
    operation: () async throws -> R
) async rethrows -> R {
    try await DependencyValues.$_current.withValue(snapshot, operation: operation)
}

// MARK: - Snapshot for escaping closures

/// A `Sendable` snapshot of the current `DependencyValues`, suitable for
/// crossing isolation/concurrency boundaries that don't propagate TaskLocals.
public struct DependencyContinuation: Sendable {
    @usableFromInline
    let snapshot: DependencyValues

    @usableFromInline
    init(snapshot: DependencyValues) {
        self.snapshot = snapshot
    }

    /// Re-bind the captured dependencies for the duration of `operation`.
    @discardableResult
    public func yield<R>(operation: () throws -> R) rethrows -> R {
        try DependencyValues.$_current.withValue(snapshot, operation: operation)
    }

    /// Re-bind asynchronously.
    @discardableResult
    public func yield<R: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> R
    ) async rethrows -> R {
        try await DependencyValues.$_current.withValue(snapshot, operation: operation)
    }
}

/// Capture the active dependencies into a `Sendable` snapshot.
///
/// Use this immediately before sending work into a context that does not
/// propagate `@TaskLocal` (Combine, GCD, `Task.detached`,
/// `NotificationCenter`):
///
/// ```swift
/// let continuation = captureDependencies()
/// DispatchQueue.global().async {
///     continuation.yield {
///         // Dependencies are visible here.
///     }
/// }
/// ```
public func captureDependencies() -> DependencyContinuation {
    DependencyContinuation(snapshot: DependencyValues.current)
}

// MARK: - Capture ergonomics

extension DependencyContinuation {
    /// Wrap a `@Sendable` closure so each invocation rebinds the captured
    /// dependencies before running `operation`.
    ///
    /// Useful when handing a closure to a callback-style API:
    ///
    /// ```swift
    /// callbackAPI.start(handler: captureDependencies().wrap { event in
    ///     // Dependencies are visible regardless of which thread the API
    ///     // dispatches the handler on.
    /// })
    /// ```
    public func wrap<each Argument: Sendable, R: Sendable>(
        _ operation: @escaping @Sendable (repeat each Argument) -> R
    ) -> @Sendable (repeat each Argument) -> R {
        let snapshot = self.snapshot
        return { (argument: repeat each Argument) in
            DependencyValues.$_current.withValue(snapshot) {
                operation(repeat each argument)
            }
        }
    }

    /// Throwing variant of ``wrap(_:)``.
    public func wrap<each Argument: Sendable, R: Sendable>(
        _ operation: @escaping @Sendable (repeat each Argument) throws -> R
    ) -> @Sendable (repeat each Argument) throws -> R {
        let snapshot = self.snapshot
        return { (argument: repeat each Argument) in
            try DependencyValues.$_current.withValue(snapshot) {
                try operation(repeat each argument)
            }
        }
    }
}

/// Synchronous form: capture dependencies, hand the resulting
/// ``DependencyContinuation`` to `operation`, and return its result.
///
/// Reduces the chance of capturing too early — the snapshot is always taken
/// inside the call, immediately before the boundary-crossing work.
///
/// ```swift
/// let result = withCapturedDependencies { continuation in
///     callbackAPI.startSync {
///         continuation.yield {
///             // Dependencies visible here.
///         }
///     }
/// }
/// ```
@discardableResult
public func withCapturedDependencies<R>(
    _ operation: (DependencyContinuation) throws -> R
) rethrows -> R {
    try operation(captureDependencies())
}

/// Async form of ``withCapturedDependencies(_:)``.
///
/// Inherits the caller's actor isolation via `#isolation`.
@discardableResult
public func withCapturedDependencies<R: Sendable>(
    isolation: isolated (any Actor)? = #isolation,
    _ operation: (DependencyContinuation) async throws -> R
) async rethrows -> R {
    try await operation(captureDependencies())
}
