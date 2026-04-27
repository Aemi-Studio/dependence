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
/// Overrides propagate to child structured tasks (`async let`, `withTaskGroup`'s
/// `addTask`) automatically because they ride on `@TaskLocal`.
/// `Task.detached` and unstructured callbacks (Combine, GCD,
/// `NotificationCenter`) do **not** inherit; use ``captureDependencies(_:)``
/// to snapshot and rebind across those boundaries.
@discardableResult
public func withDependencies<R>(
    _ mutate: (inout DependencyValues) throws -> Void,
    operation: () throws -> R
) rethrows -> R {
    var copy = DependencyValues._current
    try mutate(&copy)
    return try DependencyValues.$_current.withValue(copy, operation: operation)
}

// MARK: - Async overrides

/// Async form of ``withDependencies(_:operation:)-9aaby``.
///
/// Inherits the caller's actor isolation via `#isolation` so overrides set
/// on `@MainActor` propagate without forcing a hop.
@discardableResult
public func withDependencies<R: Sendable>(
    _ mutate: (inout DependencyValues) throws -> Void,
    isolation: isolated (any Actor)? = #isolation,
    operation: () async throws -> R
) async rethrows -> R {
    var copy = DependencyValues._current
    try mutate(&copy)
    return try await DependencyValues.$_current.withValue(copy, operation: operation)
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
    DependencyContinuation(snapshot: DependencyValues._current)
}
