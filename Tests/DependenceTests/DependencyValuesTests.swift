//
//  DependencyValuesTests.swift
//  DependenceTests
//

@testable import Dependence
import DependenceTesting
import Foundation
import Testing

/// Regression suite for ``IssueContext`` detection order. The test process
/// has `Testing.framework` (and likely `XCTest`) loaded — the only signal
/// that should reliably promote a process to `.preview` is the
/// `XCODE_RUNNING_FOR_PREVIEWS` env var, which Xcode's preview shim sets.
/// Detection MUST consult that env var ahead of test-framework probes,
/// otherwise SwiftUI Previews resolve to `liveValue`/`testValue` instead of
/// `previewValue` and `@DependencyEntry(preview:)` registrations are
/// effectively ignored at preview time.
@Suite("IssueContext detection", .serialized)
struct IssueContextDetectionTests {

    @Test("Preview env var wins against an active test framework")
    func previewEnvVarTakesPrecedence() {
        let key = "XCODE_RUNNING_FOR_PREVIEWS"
        let prior = ProcessInfo.processInfo.environment[key]
        setenv(key, "1", 1)
        defer {
            if let prior {
                setenv(key, prior, 1)
            } else {
                unsetenv(key)
            }
        }
        #expect(IssueContext.current == .preview)
    }
}

@Suite("DependencyValues")
struct DependencyValuesTests {

    // A dummy dependency used by these tests.
    struct Greeter: Sendable {
        var greet: @Sendable () -> String
    }

    enum GreeterKey: DependencyKey {
        static var liveValue: Greeter { Greeter(greet: { "live" }) }
        static var testValue: Greeter { Greeter(greet: { "test" }) }
        static var previewValue: Greeter { Greeter(greet: { "preview" }) }
    }

    @Test("Default resolution picks the testValue under Swift Testing")
    func defaultResolution() {
        let g = DependencyValues.current[GreeterKey.self]
        #expect(g.greet() == "test")
    }

    @Test("withDependencies override propagates to sync code")
    func syncOverride() {
        withDependencies {
            $0[GreeterKey.self] = Greeter(greet: { "override" })
        } operation: {
            #expect(DependencyValues.current[GreeterKey.self].greet() == "override")
        }
    }

    @Test("withDependencies override propagates across async let")
    func asyncLetPropagation() async {
        await withDependencies {
            $0[GreeterKey.self] = Greeter(greet: { "async" })
        } operation: {
            async let value = readGreeter()
            #expect(await value == "async")
        }
    }

    private func readGreeter() async -> String {
        DependencyValues.current[GreeterKey.self].greet()
    }

    @Test("Detached tasks do NOT inherit overrides without captureDependencies")
    func detachedDoesNotInherit() async {
        let observed: String = await withDependencies {
            $0[GreeterKey.self] = Greeter(greet: { "scoped" })
        } operation: {
            await Task.detached {
                DependencyValues.current[GreeterKey.self].greet()
            }.value
        }
        #expect(observed == "test")
    }

    @Test("captureDependencies bridges to a detached task")
    func captureDependenciesBridges() async {
        let observed: String = await withDependencies {
            $0[GreeterKey.self] = Greeter(greet: { "captured" })
        } operation: {
            let continuation = captureDependencies()
            return await Task.detached {
                continuation.yield {
                    DependencyValues.current[GreeterKey.self].greet()
                }
            }.value
        }
        #expect(observed == "captured")
    }

    // Regression test: under the old implementation `resolve(_:)` held the
    // cache lock while computing `K.liveValue`/`testValue`. A live-value
    // getter that reached for another `@Dependency` re-entered the lock and
    // deadlocked. The two-phase resolve installs values *outside* the lock,
    // so this composition completes deterministically.
    struct Outer: Sendable {
        var inner: String
    }
    enum InnerKey: DependencyKey {
        static var liveValue: String { "inner-live" }
        static var testValue: String { "inner-test" }
    }
    enum OuterKey: DependencyKey {
        static var liveValue: Outer {
            // Read another @Dependency inside the live-value getter. Pre-fix
            // this would deadlock on `cache`.
            Outer(inner: DependencyValues.current[InnerKey.self])
        }
        static var testValue: Outer {
            Outer(inner: DependencyValues.current[InnerKey.self])
        }
    }

    @Test("liveValue may read another @Dependency without deadlocking the cache")
    func cacheReentryDoesNotDeadlock() async {
        // If the cache lock was held during default computation this call
        // would hang; the test framework's timeout would surface it. We
        // assert the resolved value too, so a silent "no deadlock but wrong
        // value" regression also fails loudly.
        let value = DependencyValues.current[OuterKey.self]
        #expect(value.inner == "inner-test")
    }
}
