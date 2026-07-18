//
//  TestClockTests.swift
//  DependenceTestingTests
//

import DependenceTesting
import Synchronization
import Testing

@Suite("TestClock")
struct TestClockTests {
    @Test("advance resumes pending sleepers")
    func advance() async {
        let clock = TestClock()
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                try? await clock.sleep(for: .seconds(2))
                return "two"
            }
            group.addTask {
                try? await clock.sleep(for: .seconds(1))
                return "one"
            }
            // Rendezvous: both children have registered their sleepers.
            // Without this the advance below can race the registrations and
            // strand a sleeper whose deadline is then computed against the
            // already-advanced clock.
            try? await clock.waitForSleepers(count: 2)
            await clock.advance(by: .seconds(2))
            var collected: [String] = []
            for await value in group { collected.append(value) }
            #expect(collected.contains("one"))
            #expect(collected.contains("two"))
        }
    }

    @Test("advance to a deadline before the earliest sleeper does not resume it")
    func advancePartial() async {
        let clock = TestClock()
        await withTaskGroup(of: Void.self) { group in
            let resumed = Mutex(false)
            group.addTask {
                try? await clock.sleep(for: .seconds(5))
                resumed.withLock { $0 = true }
            }
            try? await clock.waitForSleepers()
            await clock.advance(by: .seconds(1))
            #expect(resumed.withLock { $0 } == false)
            #expect(clock.now.offset == .seconds(1))
            await clock.advance(by: .seconds(5))
            for await _ in group {}
            #expect(resumed.withLock { $0 } == true)
        }
    }

    @Test("Sleepers with equal deadlines resume in FIFO registration order")
    func equalDeadlinesResumeFIFO() async {
        // The FIFO contract is about the order `advance` *resumes* the
        // continuations — asserted through the clock's resume log. The order
        // in which the resumed tasks then execute belongs to the scheduler
        // (continuation hops can legally interleave), so it is deliberately
        // not asserted on.
        let clock = TestClock()
        let first = Task {
            try? await clock.sleep(for: .seconds(1))
        }
        let second = Task {
            try? await clock.sleep(for: .seconds(1))
        }
        try? await clock.waitForSleepers(count: 2)
        await clock.advance(by: .seconds(1))
        _ = await first.value
        _ = await second.value
        let order = clock.resumeOrderForTesting
        #expect(order.count == 2)
        // IDs are allocated monotonically at registration: strictly
        // increasing resume order across the equal deadlines is FIFO.
        #expect(order == order.sorted())
        #expect(order.first != order.last)
    }

    @Test("waitForSleepers rendezvouses with a spawned sleeper without yields")
    func waitForSleepersRendezvous() async throws {
        let clock = TestClock()
        async let produced: Bool = {
            try? await clock.sleep(for: .milliseconds(50))
            return true
        }()
        try await clock.waitForSleepers()
        #expect(clock.pendingSleeperCount == 1)
        await clock.advance(by: .milliseconds(50))
        #expect(await produced)
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test("waitForSleepers throws CancellationError when its task is cancelled")
    func waitForSleepersCancellation() async {
        let clock = TestClock()
        let waiter = Task {
            do {
                try await clock.waitForSleepers()
                return "satisfied"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other"
            }
        }
        waiter.cancel()
        #expect(await waiter.value == "cancelled")
    }

    @Test("sleep on an already-cancelled task throws without registering a sleeper")
    func sleepOnCancelledTaskThrowsImmediately() async {
        let clock = TestClock()
        let task = Task { () -> String in
            // Self-cancel makes the pre-cancelled state deterministic — no
            // yields, no racing an external `cancel()` against task startup.
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await clock.sleep(for: .seconds(60))
                return "completed"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other:\(type(of: error))"
            }
        }
        #expect(await task.value == "cancelled")
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test("Cancellation after registration resumes the sleeper with CancellationError")
    func cancellationAfterRegistration() async {
        let clock = TestClock()
        let task = Task { () -> String in
            do {
                try await clock.sleep(for: .seconds(60))
                return "completed"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other:\(type(of: error))"
            }
        }
        // Deterministic: the sleeper is registered *now* — the cancellation
        // below exercises the remove-under-the-same-lock path, not the
        // pre-registration shortcut.
        try? await clock.waitForSleepers()
        #expect(clock.pendingSleeperCount == 1)
        task.cancel()
        #expect(await task.value == "cancelled")
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test("run() drains sleepers scheduled at distinct deadlines")
    func runDrainsSleepers() async {
        let clock = TestClock()
        let completions = Mutex(0)
        await withTaskGroup(of: Void.self) { group in
            for i in 1...3 {
                group.addTask {
                    try? await clock.sleep(for: .seconds(Int64(i)))
                    completions.withLock { $0 += 1 }
                }
            }
            try? await clock.waitForSleepers(count: 3)
            await clock.run()
            for await _ in group {}
        }
        #expect(completions.withLock { $0 } == 3)
        #expect(clock.now.offset == .seconds(3))
    }

    @Test("run() reports and bails out when the advancement cap is exceeded")
    func runCapReportsSelfReschedulingLivelock() async {
        // A genuine 1000-pass livelock needs the resumed task to re-register
        // between every two run() passes — scheduler-dependent and therefore
        // untestable deterministically. Pin the capped branch through the
        // package seam instead: any pending sleeper with a cap of 0 must
        // trip the report and leave the queue untouched.
        let clock = TestClock()
        let sleeper = Task {
            try await clock.sleep(for: .seconds(1))
        }
        try? await clock.waitForSleepers()
        await withKnownIssue("run() must report when the cap is exceeded") {
            await clock.run(advancementCap: 0)
        }
        // The capped run() returned with the sleeper still pending.
        #expect(clock.pendingSleeperCount == 1)
        sleeper.cancel()
        await #expect(throws: CancellationError.self) {
            try await sleeper.value
        }
        #expect(clock.pendingSleeperCount == 0)
    }

    @Test("ImmediateClock returns from sleep without waiting")
    func immediateClock() async throws {
        let clock = ImmediateClock()
        try await clock.sleep(for: .seconds(1_000_000))
        // Time advances locally so the offset has moved.
        #expect(clock.now.offset >= .seconds(1_000_000))
    }

    @Test("ImmediateClock.sleep honors task cancellation")
    func immediateClockCancellation() async {
        let clock = ImmediateClock()
        let task = Task { () -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await clock.sleep(for: .seconds(1))
                return "completed"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other"
            }
        }
        #expect(await task.value == "cancelled")
    }
}
