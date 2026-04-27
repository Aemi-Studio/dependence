//
//  BridgeTests.swift
//  DependenceAppIntentsTests
//
//  Smoke tests for the AppDependencyManager <-> DependencyValues bridge.
//
//  Full round-trip tests (registering a value and reading it back through
//  `AppDependency`) require an `AppIntent` / `EntityQuery` host — `AppDependency`
//  itself crashes outside `_SupportsAppDependencies` types unless its
//  `wrappedValue` has been set manually. We therefore verify only that
//  `bridge(_:)` compiles and runs against a standalone manager. The bridged
//  closure is exercised the moment AppIntents asks for the value, which
//  the framework's dispatcher does internally; we don't reach into that here.
//

#if canImport(AppIntents)
import AppIntents
import Dependence
import DependenceAppIntents
import Testing

@Suite("AppDependencyManager + Dependence")
struct BridgeTests {

    @Test("bridge(_:) accepts a DependencyValues key path on a standalone manager")
    func bridgeKeyPath() {
        let manager = AppDependencyManager()
        manager.bridge(\.bridgeProbe)
    }

    @Test("bridge(_:) accepts a disambiguation key")
    func bridgeKeyed() {
        let manager = AppDependencyManager()
        manager.bridge(\.bridgeProbe, key: "primary")
        manager.bridge(\.bridgeProbe, key: "secondary")
    }

    @Test("bridge(test:) accepts an interface-only TestDependencyKey")
    func bridgeTestKey() {
        let manager = AppDependencyManager()
        manager.bridge(test: BridgeProbeKey.self)
    }
}

// MARK: - Probes

private struct BridgeProbe: Sendable {
    let stamp: Int
}

private enum BridgeProbeKey: TestDependencyKey {
    typealias Value = BridgeProbe
    static var testValue: BridgeProbe { BridgeProbe(stamp: 0) }
}

extension DependencyValues {
    fileprivate var bridgeProbe: BridgeProbe {
        get { self[BridgeProbeLiveKey.self] }
        set { self[BridgeProbeLiveKey.self] = newValue }
    }
}

private enum BridgeProbeLiveKey: DependencyKey {
    typealias Value = BridgeProbe
    static var liveValue: BridgeProbe { BridgeProbe(stamp: 1) }
}
#endif
