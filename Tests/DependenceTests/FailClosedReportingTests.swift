//
//  FailClosedReportingTests.swift
//  DependenceTests
//
//  Pins the fail-closed reporting chain: misconfigurations that used to
//  degrade silently (interface-only keys in a live process, live values
//  standing in for test values, resolution cycles) must be loud.
//

@_spi(TestSupport) import Dependence
import DependenceTesting
import Foundation
import Testing

@testable import Dependence

// The no-op `.dependencies` trait installs the Swift Testing issue-routing
// handler for this bundle (required for `withKnownIssue` to observe
// `reportIssue` under the SwiftBuild backend, where every test target runs
// as its own bundle). Nested under `ProcessGlobalStateSuites` because the
// suite wipes the process-wide resolution cache — see that file for why
// sibling-level `.serialized` is not enough.
extension ProcessGlobalStateSuites {
    @Suite("Fail-closed reporting", .dependencies { _ in })
    struct FailClosedReportingTests {
        private func resetRuntime() {
            DependencyRuntimeState.resetForTesting()
        }

        // MARK: - Interface-only key in a runtime context (F2b)

        private struct InterfaceOnly: Sendable, Equatable {
            var tag: String
        }

        private enum InterfaceOnlyKey: TestDependencyKey {
            static var testValue: InterfaceOnly { InterfaceOnly(tag: "test") }
        }

        @Test("Interface-only key resolving in a runtime context reports and falls back to testValue")
        func interfaceOnlyKeyInRuntimeContextReports() {
            resetRuntime()
            defer { resetRuntime() }

            var observed: InterfaceOnly?
            withKnownIssue("a live process resolving an interface-only key is a wiring bug") {
                observed = DependencyValues.resolveTest(InterfaceOnlyKey.self, context: .runtime)
            }
            // Loud, but still recoverable: the testValue is returned.
            #expect(observed == InterfaceOnly(tag: "test"))
        }

        @Test("Interface-only key resolution stays silent under test and preview contexts")
        func interfaceOnlyKeyInTestContextStaysSilent() {
            resetRuntime()
            defer { resetRuntime() }

            // No withKnownIssue: an unexpected reportIssue would fail this test.
            let testResolved = DependencyValues.resolveTest(InterfaceOnlyKey.self, context: .swiftTesting)
            #expect(testResolved == InterfaceOnly(tag: "test"))

            resetRuntime()
            let previewResolved = DependencyValues.resolveTest(InterfaceOnlyKey.self, context: .preview)
            // previewValue defaults to testValue for this key.
            #expect(previewResolved == InterfaceOnly(tag: "test"))
        }

        // MARK: - Default testValue = liveValue under a test context (F2c)

        private struct LiveOnly: Sendable, Equatable {
            var tag: String
        }

        /// A key that deliberately declares no `testValue`.
        ///
        /// The protocol default falls back to `liveValue`, which must be
        /// loud in tests. The explicit typealias is required for any
        /// liveValue-only key: `Value` is inferred at the
        /// `TestDependencyKey` conformance, which never sees `liveValue`.
        private enum LiveOnlyKey: DependencyKey {
            typealias Value = LiveOnly

            static var liveValue: LiveOnly { LiveOnly(tag: "live") }
        }

        @Test("testValue defaulting to liveValue reports under Swift Testing")
        func defaultTestValueFallbackReportsInTests() {
            resetRuntime()
            defer { resetRuntime() }

            var observed: LiveOnly?
            withKnownIssue("silently running the live value in tests must be loud") {
                observed = DependencyValues()[LiveOnlyKey.self]
            }
            #expect(observed == LiveOnly(tag: "live"))
        }

        /// Explicit `testValue = liveValue` is the documented opt-out for keys
        /// whose live value is genuinely test-safe.
        private enum OptedOutKey: DependencyKey {
            static var liveValue: LiveOnly { LiveOnly(tag: "live") }
            static var testValue: LiveOnly { Self.liveValue }
        }

        @Test("Spelling out testValue = liveValue resolves silently in tests")
        func explicitLiveFallbackStaysSilent() {
            resetRuntime()
            defer { resetRuntime() }

            // No withKnownIssue: the explicit witness must not report.
            #expect(DependencyValues()[OptedOutKey.self] == LiveOnly(tag: "live"))
        }

        // MARK: - Cycle detection (F2d)

        @Test(
            "A default value that resolves its own key traps with a cycle diagnostic instead of overflowing the stack"
        )
        func cycleTrapsWithDiagnostic() async {
            await #expect(processExitsWith: .failure) {
                // In the child process this resolves under the Swift Testing
                // context: CyclicProbeKey.testValue re-resolves its own key while
                // the first computation is still in flight, which the cycle guard
                // must turn into a deterministic trap (previously: stack
                // overflow).
                _ = DependencyValues()[CyclicProbeKey.self]
            }
        }

        @Test("Nested distinct-key computation is not flagged as a cycle")
        func nestedDistinctKeysAreNotACycle() {
            resetRuntime()
            defer { resetRuntime() }

            // Outer's default reads Inner while Outer is in flight — a chain,
            // not a cycle. Must resolve without reporting or trapping.
            #expect(DependencyValues()[ChainOuterKey.self] == "outer(inner)")
        }
    }
}

// MARK: - Top-level probe keys

/// A key whose every default re-resolves itself.
///
/// Top-level (not nested in the suite) so the exit-test body can reference
/// it without captures.
private enum CyclicProbeKey: DependencyKey {
    static var liveValue: Int { DependencyValues()[CyclicProbeKey.self] }
    static var testValue: Int { DependencyValues()[CyclicProbeKey.self] }
}

private enum ChainInnerKey: DependencyKey {
    static var liveValue: String { "inner" }
    static var testValue: String { "inner" }
}

private enum ChainOuterKey: DependencyKey {
    static var liveValue: String { "outer(\(DependencyValues()[ChainInnerKey.self]))" }
    static var testValue: String { "outer(\(DependencyValues()[ChainInnerKey.self]))" }
}
