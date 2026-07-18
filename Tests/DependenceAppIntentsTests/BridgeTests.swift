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

        @Test("Bridged provider re-resolves on every call — later installs are honored")
        func bridgedProviderIsLazy() {
            // The provider is created BEFORE any override exists — the same
            // order as `bridge(_:)` at app launch followed by later installs.
            // A strict capture would freeze the pre-install resolution
            // forever; the @autoclosure contract requires re-resolution
            // through DependencyValues.current on every call. (Deliberately
            // exercised with task-local installs only: prepareDependencies
            // mutates the process-wide latch/cache, which would race the
            // parallel suites of other targets in the unified test process.)
            let provider = DependenceAppIntentsBridge.provider(\.bridgeProbe)
            #expect(provider().stamp == 0)

            withDependencies {
                $0.bridgeProbe = BridgeProbe(stamp: 42)
            } operation: {
                #expect(provider().stamp == 42)
            }
            withDependencies {
                $0.bridgeProbe = BridgeProbe(stamp: 7)
            } operation: {
                #expect(provider().stamp == 7)
            }
            // Back to the context default once the scopes exit.
            #expect(provider().stamp == 0)
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
        static var testValue: BridgeProbe { BridgeProbe(stamp: 0) }
    }
#endif
