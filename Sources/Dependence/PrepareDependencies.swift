//
//  PrepareDependencies.swift
//  Dependence
//
//  App-lifetime override hook. Use at the composition root before any
//  dependency is resolved.
//

import Foundation
import Synchronization

/// Configure the live dependency container once at app launch.
///
/// Call this at the very top of your `@main` `init()` (SwiftUI) or
/// `application(_:didFinishLaunchingWithOptions:)` (UIKit). It must run
/// before any `@Dependency` is read for the first time, otherwise the
/// process-wide cache will already contain the un-overridden `liveValue`s.
///
/// Calling this twice in the same process emits a runtime warning — the
/// second call is ignored.
///
/// Do **not** call this from inside a ``withDependencies(_:operation:)-(_,_)``
/// block: the prepared bag seeds from the task-local container, so any
/// scoped override in flight would be frozen into the *process-wide* cache
/// and outlive its scope. That situation is reported as an issue (the
/// install still proceeds, matching the historical behavior).
public func prepareDependencies(_ mutate: (inout DependencyValues) -> Void) {
    PrepareDependenciesState.shared.run(mutate: mutate)
}

@usableFromInline
package final class PrepareDependenciesState: Sendable {
    @usableFromInline
    static let shared = PrepareDependenciesState()

    private let didRun = Mutex<Bool>(false)

    private init() {}

    @usableFromInline
    func run(mutate: (inout DependencyValues) -> Void) {
        let alreadyRan = didRun.withLock { value -> Bool in
            defer { value = true }
            return value
        }
        if alreadyRan {
            reportIssue(
                "prepareDependencies(_:) was called more than once in this process. "
                    + "Subsequent calls are ignored — configure all live dependencies in a single composition root."
            )
            return
        }
        var copy = DependencyValues._current
        if !copy.overrides.isEmpty {
            // A withDependencies scope is active around the composition
            // root. Its task-local overrides are about to be frozen into
            // the process-wide cache — they would outlive their scope.
            // Loud, then proceed (the install has always included them).
            reportIssue(
                "prepareDependencies(_:) was called inside a withDependencies scope — the scope's "
                    + "task-local overrides (\(copy.overrides.count) key(s)) are being installed into the "
                    + "process-wide cache and will outlive the scope. Call prepareDependencies from the "
                    + "composition root, outside any scoped override."
            )
        }
        mutate(&copy)
        // The TaskLocal can only be set within a `withValue` scope. For the
        // app-lifetime case we take a different path: write each override
        // straight into the shared cache so future default resolution returns
        // these prepared values.
        DependencyValues.installInitial(copy)
    }

    /// Idempotent variant for SwiftUI Scene-level installation.
    ///
    /// `Scene.body` re-evaluates whenever any of its inputs change, so the
    /// `.dependencies(_:)` Scene modifier must be safe to call repeatedly —
    /// silently no-op'ing on every call after the first. Unlike ``run(mutate:)``
    /// this path emits no warning on repeat calls.
    @usableFromInline
    package func installIfNeeded(_ values: DependencyValues) {
        didRun.withLock { ran in
            guard !ran else { return }
            DependencyValues.installInitial(values)
            ran = true
        }
    }

    /// Resets the first-call-wins latch.
    ///
    /// A subsequent ``run(mutate:)`` or ``installIfNeeded(_:)`` re-arms the
    /// install path. **Test-only**; never call from production code.
    @_spi(TestSupport)
    public func _resetForTesting() {
        didRun.withLock { $0 = false }
    }
}

// MARK: - Test-only runtime reset (@_spi(TestSupport))

/// Aggregate test-cleanup utility for process-wide `Dependence` state.
///
/// Use from suite teardown when a test mutates the resolution cache, the
/// SwiftUI subtree stack, or the ``prepareDependencies(_:)``
/// first-call-wins latch.
///
/// **Test-only.** Behind `@_spi(TestSupport)`: importers must opt in with
/// `@_spi(TestSupport) import Dependence` to call this. Production targets
/// that do not import the SPI cannot reach the reset, preserving the
/// first-install-wins / stable-cache contract.
@_spi(TestSupport)
public enum DependencyRuntimeState {
    /// Wipe every piece of process-wide state.
    ///
    /// Specifically:
    ///
    /// 1. ``DependencyValues/cache`` — resolved defaults per `IssueContext`.
    /// 2. ``DependencyValues/_subtreeStack`` — every published SwiftUI
    ///    subtree-override entry.
    /// 3. ``PrepareDependenciesState`` — the first-call-wins latch.
    @_spi(TestSupport)
    public static func resetForTesting() {
        DependencyValues._resetCacheForTesting()
        DependencyValues._clearSubtreesForTesting()
        PrepareDependenciesState.shared._resetForTesting()
    }
}

extension DependencyValues {
    /// Install the result of `prepareDependencies` into the process-wide
    /// cache so that all subsequent `@Dependency` reads see the overrides.
    ///
    /// We achieve this by writing each override entry into the cache —
    /// `Dependency` resolution checks the cache before falling through to
    /// `liveValue`, so this effectively "freezes" the chosen values. Each
    /// override is registered under every `IssueContext` so a process that
    /// straddles boundaries (e.g. an XCTest run that triggers a preview
    /// subprocess) still sees the prepared value.
    @usableFromInline
    static func installInitial(_ values: DependencyValues) {
        cache.withLock { entries in
            for (id, value) in values.overrides {
                for context in [
                    IssueContext.runtime,
                    .preview,
                    .swiftTesting,
                    .xctest,
                ] {
                    entries[CacheKey(id: id, context: context)] = value
                }
            }
        }
    }
}
