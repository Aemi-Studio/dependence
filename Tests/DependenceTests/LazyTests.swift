//
//  LazyTests.swift
//  DependenceTests
//
//  Direct tests for `Lazy`'s one-shot semantics. The double-check pattern
//  inside `Lazy.Storage.read()` says: "compute outside the lock, install
//  inside the lock, return the first value installed." That is the contract
//  we exercise here. The companion `withDependencies`/dependency-refresh
//  tests prove `Lazy` is **not** hotloadable, which is by design and is the
//  reason a value-flavoured `Provider` exists alongside it.
//

import Dependence
import DependenceTesting
import Foundation
import Synchronization
import Testing

@Suite("Lazy semantics")
struct LazyTests {
    @Test("First read computes; subsequent reads return the cached value")
    func computesOnceAndCaches() {
        let calls = Mutex<Int>(0)
        let lazy = Lazy<Int> {
            calls.withLock { count in
                count += 1
                return count
            }
        }

        #expect(lazy() == 1)
        #expect(lazy() == 1)
        #expect(lazy() == 1)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("Producer can read another @Dependency without deadlocking the lazy lock")
    func producerReadsAnotherDependency() {
        struct DemoKey: DependencyKey {
            static var liveValue: Int { 99 }
            static var testValue: Int { 7 }
        }

        let lazy = Lazy<Int> {
            // Re-enters the resolution path. If `Lazy` held its lock during
            // the producer call, an outer caller that itself ran inside the
            // same lock would deadlock; the implementation computes outside
            // the lock specifically to avoid this.
            DependencyValues.current[DemoKey.self] * 2
        }

        withDependencies {
            $0[DemoKey.self] = 21
        } operation: {
            #expect(lazy() == 42)
        }
    }

    @Test("Replacing the underlying dependency does NOT hotload Lazy")
    func notHotloadable() {
        struct ColorKey: DependencyKey {
            static var liveValue: String { "live" }
            static var testValue: String { "test" }
        }

        // Produces a value bound to whatever override was active at first call.
        let lazy = Lazy<String> {
            DependencyValues.current[ColorKey.self]
        }

        withDependencies {
            $0[ColorKey.self] = "first"
        } operation: {
            #expect(lazy() == "first")
        }

        // A subsequent override must not be observable; the value is frozen
        // to the first installed result.
        withDependencies {
            $0[ColorKey.self] = "second"
        } operation: {
            #expect(lazy() == "first")
        }

        #expect(lazy() == "first")
    }

    @Test("Concurrent first-readers see exactly one installed value")
    func concurrentReadersAgreeOnInstalledValue() async {
        // Under contention several producers may run, but the lock's
        // double-check guarantees only one value is installed and every
        // caller observes the same value. We assert the agreement, not the
        // producer-call count, because the latter is intentionally racy.
        let attempts = Mutex<[Int]>([])
        let nextAttempt = Mutex<Int>(0)
        let lazy = Lazy<Int> {
            let attempt = nextAttempt.withLock { value in
                value += 1
                return value
            }
            attempts.withLock { $0.append(attempt) }
            return attempt
        }

        let observed: [Int] = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<32 {
                group.addTask { lazy() }
            }
            var collected: [Int] = []
            for await value in group {
                collected.append(value)
            }
            return collected
        }

        let installed = lazy()
        #expect(observed.allSatisfy { $0 == installed })
        // Producer attempts must have been *finite* — bound by reader count.
        #expect(attempts.withLock { $0.count <= 32 })
    }
}
