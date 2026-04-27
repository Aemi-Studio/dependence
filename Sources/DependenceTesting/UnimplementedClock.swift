//
//  UnimplementedClock.swift
//  DependenceTesting
//
//  A clock that surfaces an `Issue.record` whenever it's used. Acts as the
//  default `testValue` for clock dependencies — calling code that forgets to
//  inject a clock will fail loudly rather than slow tests down with real
//  sleeps.
//

import Dependence
import Foundation

/// A `Clock` that records an issue on every interaction.
///
/// Use as the default `testValue` for clock-shaped dependencies:
///
/// ```swift
/// extension DependencyValues {
///     @DependencyEntry public var clock: any Clock<Duration> = UnimplementedClock()
/// }
/// ```
///
/// Any test that exercises a code path consuming the clock without first
/// overriding it will fail with a clear "unimplemented" issue, instead of
/// silently sleeping or producing bogus timing.
public struct UnimplementedClock: Clock, Sendable {
    public typealias Instant = ImmediateClock.Instant
    public typealias Duration = Swift.Duration

    private let label: String
    private let inner: ImmediateClock

    public var minimumResolution: Swift.Duration {
        reportIssue("UnimplementedClock(\(label)).minimumResolution accessed")
        return inner.minimumResolution
    }

    public var now: Instant {
        reportIssue("UnimplementedClock(\(label)).now accessed")
        return inner.now
    }

    public init(_ label: String = "Clock") {
        // Ensure Swift Testing routing is installed before we ever emit an
        // `unimplemented` issue from this clock.
        _ = _SwiftTestingIssueRouting.bootstrap
        self.label = label
        self.inner = ImmediateClock()
    }

    public func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        reportIssue("UnimplementedClock(\(label)).sleep called")
        try await inner.sleep(until: deadline, tolerance: tolerance)
    }
}
