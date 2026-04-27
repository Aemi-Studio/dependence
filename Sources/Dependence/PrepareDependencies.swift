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
                "prepareDependencies(_:) was called more than once in this process. " +
                "Subsequent calls are ignored — configure all live dependencies in a single composition root."
            )
            return
        }
        var copy = DependencyValues._current
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
