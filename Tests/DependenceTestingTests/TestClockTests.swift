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
            await clock.advance(by: .seconds(1))
            #expect(resumed.withLock { $0 } == false)
            await clock.advance(by: .seconds(5))
            for await _ in group {}
            #expect(resumed.withLock { $0 } == true)
        }
    }

    @Test("ImmediateClock returns from sleep without waiting")
    func immediateClock() async throws {
        let clock = ImmediateClock()
        try await clock.sleep(for: .seconds(1_000_000))
        // Time advances locally so the offset has moved.
        #expect(clock.now.offset >= .seconds(1_000_000))
    }

    @Test("TestClock.sleep resumes with CancellationError when the task is cancelled")
    func testClockCancellation() async {
        let clock = TestClock()
        let task = Task {
            do {
                try await clock.sleep(for: .seconds(60))
                return "completed"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other:\(type(of: error))"
            }
        }
        // Yield once so the sleeper is registered before we cancel.
        await Task.yield()
        await Task.yield()
        task.cancel()
        let outcome = await task.value
        #expect(outcome == "cancelled")
    }

    @Test("ImmediateClock.sleep honors task cancellation")
    func immediateClockCancellation() async {
        let clock = ImmediateClock()
        let task = Task {
            do {
                try await clock.sleep(for: .seconds(1))
                return "completed"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other"
            }
        }
        task.cancel()
        let outcome = await task.value
        #expect(outcome == "cancelled")
    }
}
