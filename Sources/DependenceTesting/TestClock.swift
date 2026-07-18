//
//  TestClock.swift
//  DependenceTesting
//
//  Native deterministic test clock. Suspensions block until the test code
//  explicitly advances the clock, making time-based code paths fully
//  controllable from a test.
//

import Dependence
import Foundation
import Synchronization

/// A `Clock` whose progression is driven entirely by the test.
///
/// `await clock.sleep(for: .seconds(1))` suspends until the test calls
/// `await clock.advance(by: .seconds(1))` (or further). The advance call
/// resumes every sleeper whose deadline is now in the past in deadline
/// order — ties resume in FIFO (registration) order — before returning,
/// guaranteeing deterministic resumption.
///
/// ## Rendezvous before advancing
///
/// `sleep` computes its deadline from `now` *at the moment it is called*. If
/// the test advances the clock before a spawned task has actually reached
/// `sleep`, the clock moves first and the late sleeper's deadline lands in
/// the future — it then waits forever. `Task.yield()` papers over this in
/// practice but is non-deterministic under load. Use
/// ``waitForSleepers(count:)`` to rendezvous instead — it suspends until the
/// requested number of sleepers are pending, whichever side of the race the
/// spawned task ended up on:
///
/// ```swift
/// @Test func tickTimer() async throws {
///     let clock = TestClock()
///     try await withDependencies {
///         $0.continuousClock = clock
///     } operation: {
///         async let result = produceAfterOneSecond()
///         try await clock.waitForSleepers()     // production reached sleep
///         await clock.advance(by: .seconds(1))  // release the sleeper
///         #expect(await result == "done")
///     }
/// }
/// ```
public final class TestClock: Clock, Sendable {
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

    /// One suspended `sleep` call. `id` is allocated at registration and
    /// doubles as the FIFO tie-breaker for equal deadlines.
    private struct Sleeper {
        let id: UInt64
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// One suspended ``waitForSleepers(count:)`` call. `remaining` counts
    /// down as new sleepers register ("N more" semantics).
    private struct RegistrationWaiter {
        let id: UInt64
        var remaining: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Instant = Instant(offset: .zero)
        var nextSleeperID: UInt64 = 0
        var nextWaiterID: UInt64 = 0
        var sleepers: [Sleeper] = []
        var registrationWaiters: [RegistrationWaiter] = []
        /// IDs of sleepers in the order advancement resumed them.
        ///
        /// Purely a test-observability log: the *resume-call* order is the
        /// FIFO contract; the order in which resumed tasks subsequently
        /// execute belongs to the scheduler and is deliberately not
        /// asserted on.
        var resumeLog: [UInt64] = []
    }

    /// Resolution outcome of a `sleep` registration attempt.
    private enum SleepOutcome {
        case cancelled
        case deadlineAlreadyPast
        case suspended
    }

    /// Resolution outcome of a `waitForSleepers` registration attempt.
    private enum WaitOutcome {
        case cancelled
        case alreadySatisfied
        case queued
    }

    /// Upper bound on ``run()`` advancement passes before it bails out and
    /// reports a self-rescheduling livelock.
    private static let runAdvancementCap = 1000

    private let state: Mutex<State>

    public var minimumResolution: Swift.Duration { .zero }

    public var now: Instant {
        state.withLock { $0.now }
    }

    /// Number of currently suspended sleepers.
    ///
    /// Exposed for tests that assert no sleeper leaks across a cancellation.
    package var pendingSleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    /// Sleeper IDs in the order advancement resumed them.
    ///
    /// IDs are allocated monotonically at registration, so a strictly
    /// increasing log across equal deadlines *is* the FIFO guarantee.
    /// Exposed for tests.
    package var resumeOrderForTesting: [UInt64] {
        state.withLock { $0.resumeLog }
    }

    public init(now: Instant = Instant(offset: .zero)) {
        // Install Swift Testing issue routing before `run()`'s livelock
        // report (or any other `reportIssue`) can fire from this clock.
        _ = Bootstrap.once
        var initial = State()
        initial.now = now
        self.state = Mutex(initial)
    }

    // MARK: Clock

    public func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        try Task.checkCancellation()
        // Pre-allocate the sleeper ID *before* installing the cancellation
        // handler. `onCancel` can then always target this exact sleeper —
        // there is no publish window between "continuation stored" and "ID
        // visible to the handler" (the historical race: an ID published via
        // a second lock after registration let a concurrent cancellation
        // read `nil` and leave the stored continuation suspended forever).
        let sleeperID: UInt64 = state.withLock { state in
            state.nextSleeperID &+= 1
            return state.nextSleeperID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Register the sleeper AND satisfy registration waiters in
                // one critical section. `Task.isCancelled` is checked inside
                // the same lock the cancellation handler takes: either the
                // handler ran first (we observe `isCancelled == true` and
                // never store the continuation) or we store first (the
                // handler finds and resumes it). No third interleaving.
                let (outcome, waitersToResume) = state.withLock {
                    state -> (SleepOutcome, [CheckedContinuation<Void, any Error>]) in
                    if Task.isCancelled {
                        return (.cancelled, [])
                    }
                    if deadline <= state.now {
                        return (.deadlineAlreadyPast, [])
                    }
                    state.sleepers.append(
                        Sleeper(id: sleeperID, deadline: deadline, continuation: continuation)
                    )
                    // "One more sleeper registered": decrement every waiter,
                    // collecting those whose target is now met. Resumed
                    // outside the lock to avoid re-entrancy into the clock.
                    var resumed: [CheckedContinuation<Void, any Error>] = []
                    var stillWaiting: [RegistrationWaiter] = []
                    for var waiter in state.registrationWaiters {
                        waiter.remaining -= 1
                        if waiter.remaining <= 0 {
                            resumed.append(waiter.continuation)
                        } else {
                            stillWaiting.append(waiter)
                        }
                    }
                    state.registrationWaiters = stillWaiting
                    return (.suspended, resumed)
                }
                switch outcome {
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .deadlineAlreadyPast:
                        continuation.resume()
                    case .suspended:
                        break
                }
                for waiter in waitersToResume {
                    waiter.resume()
                }
            }
        } onCancel: {
            // Remove-and-resume under the same lock that stored the
            // continuation. `nil` means the sleeper either never registered
            // (the in-lock `isCancelled` check handles it) or was already
            // resumed by an advancement.
            let cancelled = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == sleeperID }) else {
                    return nil
                }
                let continuation = state.sleepers[index].continuation
                state.sleepers.remove(at: index)
                return continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    // MARK: Rendezvous

    /// Suspends until at least `count` sleepers are pending — counting both
    /// sleepers already suspended at the time of the call and ones that
    /// register afterwards.
    ///
    /// This is the deterministic replacement for `Task.yield()` before an
    /// ``advance(by:)``: it resumes exactly when the spawned production code
    /// has reached its `sleep` call, so the subsequent advancement is
    /// guaranteed to see the sleeper. Already-pending sleepers are counted
    /// **atomically at registration**, so the rendezvous cannot hang when a
    /// spawned task (an `async let`, a `group.addTask` child) wins the race
    /// and reaches its `sleep` before this call registers its waiter —
    /// "wait for N *more*" semantics would count down from the wrong
    /// baseline in that interleaving and never resume.
    ///
    /// When earlier gated sleepers are deliberately still suspended, account
    /// for them in `count`: "one sleeper parked from phase one, now waiting
    /// for phase two's" is `waitForSleepers(count: 2)`.
    ///
    /// - Throws: `CancellationError` if the waiting task is cancelled before
    ///   the count is satisfied.
    public func waitForSleepers(count: Int = 1) async throws {
        precondition(count >= 1, "waitForSleepers(count:) requires count >= 1")
        try Task.checkCancellation()
        let waiterID: UInt64 = state.withLock { state in
            state.nextWaiterID &+= 1
            return state.nextWaiterID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome = state.withLock { state -> WaitOutcome in
                    if Task.isCancelled {
                        return .cancelled
                    }
                    // Count sleepers that are already suspended *inside the
                    // same critical section* that registers the waiter —
                    // there is no window in which a sleeper can register
                    // without either being counted here or decrementing the
                    // waiter below.
                    let remaining = count - state.sleepers.count
                    if remaining <= 0 {
                        return .alreadySatisfied
                    }
                    state.registrationWaiters.append(
                        RegistrationWaiter(id: waiterID, remaining: remaining, continuation: continuation)
                    )
                    return .queued
                }
                switch outcome {
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .alreadySatisfied:
                        continuation.resume()
                    case .queued:
                        break
                }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                guard
                    let index = state.registrationWaiters.firstIndex(where: { $0.id == waiterID })
                else {
                    return nil
                }
                let continuation = state.registrationWaiters[index].continuation
                state.registrationWaiters.remove(at: index)
                return continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    // MARK: Advancement

    /// Advance the clock by `duration`, resuming any sleepers whose
    /// deadlines fall on or before the new `now` in deadline order (FIFO
    /// for equal deadlines).
    public func advance(by duration: Swift.Duration) async {
        await advance(to: now.advanced(by: duration))
    }

    /// Advance the clock to `target`, resuming sleepers in deadline order
    /// (FIFO registration order for equal deadlines).
    ///
    /// Sleepers are resumed one at a time, yielding between resumptions, so
    /// a resumed task that immediately re-sleeps with a deadline at or
    /// before `target` is picked up by the same advancement. Prefer
    /// ``waitForSleepers(count:)`` before calling this — the up-front yield
    /// below only gives *already scheduled* tasks a best-effort chance to
    /// register and is not a synchronization point.
    public func advance(to target: Instant) async {
        await Task.yield()
        while true {
            let resumed = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                guard target >= state.now else { return nil }
                // Earliest deadline wins; the monotonically allocated `id`
                // breaks ties in registration order, matching the type-level
                // determinism contract.
                let earliest = state.sleepers.min {
                    ($0.deadline, $0.id) < ($1.deadline, $1.id)
                }
                guard let earliest else {
                    state.now = target
                    return nil
                }
                if earliest.deadline > target {
                    state.now = target
                    return nil
                }
                state.now = earliest.deadline
                if let index = state.sleepers.firstIndex(where: { $0.id == earliest.id }) {
                    state.sleepers.remove(at: index)
                }
                state.resumeLog.append(earliest.id)
                return earliest.continuation
            }
            guard let continuation = resumed else { return }
            continuation.resume()
            // Yield so the resumed task gets a chance to run before we
            // potentially resume the next one.
            await Task.yield()
        }
    }

    /// Advance to the latest pending deadline, draining every sleeper.
    ///
    /// Bounded: a sleeper that re-registers itself on every resumption would
    /// otherwise livelock this loop. After 1000 advancement passes `run()`
    /// reports an issue describing the self-rescheduling pattern and returns
    /// with the remaining sleepers still pending — drive such code with
    /// explicit ``advance(by:)`` / ``waitForSleepers(count:)`` steps instead.
    public func run() async {
        await run(advancementCap: Self.runAdvancementCap)
    }

    /// Bounded ``run()`` core with an explicit advancement-pass cap.
    ///
    /// Package-visible so tests can pin the capped branch deterministically
    /// without staging a real 1000-pass livelock (whose reproduction depends
    /// on scheduler interleaving).
    package func run(advancementCap: Int) async {
        var passes = 0
        while state.withLock({ !$0.sleepers.isEmpty }) {
            passes += 1
            if passes > advancementCap {
                reportIssue(
                    "TestClock.run() exceeded \(advancementCap) advancement passes — a sleeper "
                        + "appears to re-schedule itself on every resumption (self-rescheduling livelock). "
                        + "Returning with sleepers still pending; drive the clock with explicit "
                        + "advance(by:) / waitForSleepers(count:) steps instead."
                )
                return
            }
            let last = state.withLock { state -> Instant? in
                state.sleepers.map(\.deadline).max()
            }
            guard let last else { return }
            await advance(to: last)
        }
    }
}
