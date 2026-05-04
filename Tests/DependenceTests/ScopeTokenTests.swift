//
//  ScopeTokenTests.swift
//  DependenceTests
//

import Dependence
import Synchronization
import Testing

@Suite("ScopeToken")
struct ScopeTokenTests {
    enum DemoScope: ScopeTag {}

    @Test("enter runs operation and triggers teardown")
    func enterAndTeardown() {
        let counter = Mutex<Int>(0)
        let token = ScopeToken<DemoScope, Int>(
            value: 7,
            teardown: { counter.withLock { $0 += 1 } }
        )
        let result = token.enter { borrowed -> Int in
            borrowed.snapshot() * 2
        }
        #expect(result == 14)
        #expect(counter.withLock { $0 } == 1)
    }

    @Test("close consumes the token without running operation")
    func closeRunsTeardown() {
        let counter = Mutex<Int>(0)
        let token = ScopeToken<DemoScope, String>(
            value: "x",
            teardown: { counter.withLock { $0 += 1 } }
        )
        token.close()
        #expect(counter.withLock { $0 } == 1)
    }

    @Test("sync enter runs teardown when the operation throws")
    func syncEnterTeardownOnThrow() {
        struct Boom: Error {}
        let counter = Mutex<Int>(0)
        let token = ScopeToken<DemoScope, Int>(
            value: 1,
            teardown: { counter.withLock { $0 += 1 } }
        )
        var didThrow = false
        do {
            try token.enter { _ -> Int in throw Boom() }
        } catch is Boom {
            didThrow = true
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(didThrow)
        #expect(counter.withLock { $0 } == 1)
    }

    @Test("async enter runs teardown when the operation throws")
    func asyncEnterTeardownOnThrow() async {
        struct Boom: Error {}
        let counter = Mutex<Int>(0)
        let token = ScopeToken<DemoScope, Int>(
            value: 1,
            teardown: { counter.withLock { $0 += 1 } }
        )
        var didThrow = false
        do {
            try await token.enter { _ -> Int in
                await Task.yield()
                throw Boom()
            }
        } catch is Boom {
            didThrow = true
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(didThrow)
        #expect(counter.withLock { $0 } == 1)
    }
}
