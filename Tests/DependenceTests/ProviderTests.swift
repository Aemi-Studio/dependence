//
//  ProviderTests.swift
//  DependenceTests
//
//  `Provider` runs its factory on every call. "Freshness" is therefore a
//  property of the factory body, not of `Provider` itself: a factory that
//  reads `DependencyValues.current` is dynamic; one that captures a value
//  in its closure capture list is frozen. These tests make that distinction
//  observable.
//

import Dependence
import DependenceTesting
import Foundation
import Synchronization
import Testing

@Suite("Provider semantics")
struct ProviderTests {
    @Test("Each call invokes the factory")
    func freshPerCall() {
        let calls = Mutex<Int>(0)
        let provider = Provider<Int> {
            calls.withLock { count in
                count += 1
                return count
            }
        }

        #expect(provider() == 1)
        #expect(provider() == 2)
        #expect(provider() == 3)
        #expect(calls.withLock { $0 } == 3)
    }

    @Test("Factory body that reads DependencyValues.current observes hotloads")
    func dynamicFactoryReadsCurrent() {
        struct ToneKey: DependencyKey {
            static var liveValue: String { "live" }
            static var testValue: String { "test" }
        }

        let provider = Provider<String> {
            DependencyValues.current[ToneKey.self]
        }

        withDependencies {
            $0[ToneKey.self] = "alpha"
        } operation: {
            #expect(provider() == "alpha")
        }

        withDependencies {
            $0[ToneKey.self] = "beta"
        } operation: {
            #expect(provider() == "beta")
        }

        // Outside any override the test context returns `testValue`.
        #expect(provider() == "test")
    }

    @Test("Factory that captured a value at construction does NOT hotload")
    func capturedFactoryIsFrozen() {
        struct ToneKey: DependencyKey {
            static var liveValue: String { "live" }
            static var testValue: String { "test" }
        }

        // The provider is constructed *before* we enter any override, so the
        // capture sees `testValue`. The closure binds that value into its
        // capture list; subsequent overrides cannot reach into it.
        let captured = DependencyValues.current[ToneKey.self]
        let provider = Provider<String> { captured }

        withDependencies {
            $0[ToneKey.self] = "alpha"
        } operation: {
            #expect(provider() == "test")
        }
    }

    @Test("AsyncProvider produces fresh values on each call")
    func asyncProviderFreshPerCall() async throws {
        let calls = Mutex<Int>(0)
        let provider = AsyncProvider<Int> {
            calls.withLock { count in
                count += 1
                return count
            }
        }

        let first = try await provider()
        let second = try await provider()
        let third = try await provider()
        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)
    }

    @Test("AsyncProvider propagates errors from the factory")
    func asyncProviderPropagatesErrors() async {
        struct DemoError: Error, Equatable {}
        let provider = AsyncProvider<Int> { throw DemoError() }

        await #expect(throws: DemoError.self) {
            _ = try await provider()
        }
    }

    @Test("AsyncProvider factory observes the current TaskLocal binding")
    func asyncProviderReadsCurrent() async {
        struct ToneKey: DependencyKey {
            static var liveValue: String { "live" }
            static var testValue: String { "test" }
        }

        let provider = AsyncProvider<String> {
            DependencyValues.current[ToneKey.self]
        }

        let observed = await withDependencies {
            $0[ToneKey.self] = "scoped"
        } operation: {
            try? await provider()
        }

        #expect(observed == "scoped")
    }
}
