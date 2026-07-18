//
//  ImmediateClock.swift
//  DependenceTesting
//
//  A clock whose `sleep` calls return immediately. Useful in tests that
//  exercise time-dependent code paths without actually waiting.
//

import Dependence
import Foundation
import Synchronization

/// A `Clock` whose suspensions return immediately.
///
/// Time still advances on each call so durations can be observed for
/// assertions, but nothing actually sleeps:
///
/// ```swift
/// withDependencies {
///     $0.continuousClock = ImmediateClock()
/// } operation: {
///     // Any `try await clock.sleep(...)` returns at once.
/// }
/// ```
///
/// Conforms to `Clock` against `Duration`, matching `ContinuousClock` /
/// `SuspendingClock` so it can stand in for either at the dependency layer.
public final class ImmediateClock: Clock, Sendable {
    public typealias Duration = Swift.Duration

    public struct Instant: InstantProtocol, Sendable {
        public typealias Duration = Swift.Duration

        public var offset: Swift.Duration

        public init(offset: Swift.Duration) { self.offset = offset }

        public func advanced(by duration: Swift.Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Swift.Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private let offset: Mutex<Swift.Duration>

    public var minimumResolution: Swift.Duration { .zero }

    public var now: Instant {
        offset.withLock { Instant(offset: $0) }
    }

    public init() {
        // Every public entry point of DependenceTesting installs the Swift
        // Testing issue-routing handler, so that linking + using the module
        // in any form is enough to route `reportIssue` into `Issue.record`.
        _ = Bootstrap.once
        self.offset = Mutex(.zero)
    }

    public func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        try Task.checkCancellation()
        offset.withLock { current in
            if deadline.offset > current { current = deadline.offset }
        }
        await Task.yield()
        // `Task.yield()` does not propagate cancellation; re-check after the
        // suspension so a task cancelled mid-sleep surfaces a `CancellationError`
        // instead of silently returning success.
        try Task.checkCancellation()
    }
}
