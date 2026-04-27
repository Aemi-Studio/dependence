//
//  TestClock.swift
//  DependenceTesting
//
//  Native deterministic test clock. Suspensions block until the test code
//  explicitly advances the clock, making time-based code paths fully
//  controllable from a test.
//

import Foundation
import Synchronization

/// A `Clock` whose progression is driven entirely by the test.
///
/// `await clock.sleep(for: .seconds(1))` suspends until the test calls
/// `await clock.advance(by: .seconds(1))` (or further). The advance call
/// resumes every sleeper whose deadline is now in the past, in deadline
/// order, before returning — guaranteeing deterministic ordering.
///
/// ```swift
/// @Test func tickTimer() async {
///     let clock = TestClock()
///     await withDependencies {
///         $0.continuousClock = clock
///     } operation: {
///         async let result = produceAfterOneSecond()
///         await clock.advance(by: .seconds(1))
///         #expect(await result == "done")
///     }
/// }
/// ```
public final class TestClock: Clock, @unchecked Sendable {
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

        public static func == (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset == rhs.offset
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(offset)
        }
    }

    /// Resolution outcome from inside a state mutation.
    private enum Resolution {
        case readyToResume
        case stored(id: UInt64)
    }

    /// Outcome of a cancellation attempt against a stored sleeper.
    private enum CancellationOutcome {
        case resumeWithError(CheckedContinuation<Void, any Error>)
        case alreadyResolved
    }

    private struct State {
        var now: Instant = Instant(offset: .zero)
        var nextID: UInt64 = 0
        /// Pending sleepers keyed by ID. Resumed when the clock crosses the
        /// associated deadline or removed when the owning task is cancelled.
        var sleepers: [UInt64: (deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = [:]
    }

    private let state: Mutex<State>

    public var minimumResolution: Swift.Duration { .zero }

    public var now: Instant {
        state.withLock { $0.now }
    }

    public init(now: Instant = Instant(offset: .zero)) {
        var initial = State()
        initial.now = now
        self.state = Mutex(initial)
    }

    // MARK: Clock

    public func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        try Task.checkCancellation()
        // Track this sleep's id outside the continuation so the
        // cancellation handler can target it precisely.
        let sleepID = Mutex<UInt64?>(nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // If the task was already cancelled before we registered the
                // sleeper, surface the cancellation immediately.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let resolution = state.withLock { state -> Resolution in
                    if deadline <= state.now {
                        return .readyToResume
                    }
                    let id = state.nextID
                    state.nextID &+= 1
                    state.sleepers[id] = (deadline, continuation)
                    return .stored(id: id)
                }
                switch resolution {
                case .readyToResume:
                    continuation.resume()
                case .stored(let id):
                    sleepID.withLock { $0 = id }
                }
            }
        } onCancel: {
            // Pull the registered sleeper (if still pending) and resume it
            // with `CancellationError`. Concurrent advancement may have
            // already resolved it — in that case `outcome` is `nil` and the
            // continuation has been resumed elsewhere.
            let outcome = state.withLock { state -> CancellationOutcome? in
                guard let id = sleepID.withLock({ $0 }) else { return nil }
                guard let entry = state.sleepers.removeValue(forKey: id) else {
                    return .alreadyResolved
                }
                return .resumeWithError(entry.continuation)
            }
            switch outcome {
            case .resumeWithError(let continuation):
                continuation.resume(throwing: CancellationError())
            case .alreadyResolved, nil:
                break
            }
        }
    }

    // MARK: Advancement

    /// Advance the clock by `duration`, resuming any sleepers whose
    /// deadlines fall on or before the new `now` in deadline order.
    public func advance(by duration: Swift.Duration) async {
        await advance(to: now.advanced(by: duration))
    }

    /// Advance the clock to `target`, resuming sleepers in deadline order.
    public func advance(to target: Instant) async {
        // Yield once up front so any task that has already been spawned but
        // not yet executed gets a chance to register a sleeper before we
        // peek at the queue. This makes the common `async let … advance`
        // pattern deterministic without the test needing extra plumbing.
        await Task.yield()
        while true {
            let resumed = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                guard target >= state.now else { return nil }
                let earliest = state.sleepers.min { $0.value.deadline < $1.value.deadline }
                guard let (id, entry) = earliest else {
                    state.now = target
                    return nil
                }
                if entry.deadline > target {
                    state.now = target
                    return nil
                }
                state.now = entry.deadline
                state.sleepers.removeValue(forKey: id)
                return entry.continuation
            }
            guard let continuation = resumed else { return }
            continuation.resume()
            // Yield so the resumed task gets a chance to run before we
            // potentially resume the next one.
            await Task.yield()
        }
    }

    /// Advance to the latest pending deadline, draining every sleeper.
    public func run() async {
        while let last = state.withLock({ state -> Instant? in
            state.sleepers.values.map(\.deadline).max()
        }) {
            await advance(to: last)
        }
    }
}
