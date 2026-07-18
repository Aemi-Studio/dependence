//
//  DependencyKey.swift
//  Dependence
//
//  Identity types for dependencies. Mirrors SwiftUI's `EnvironmentKey` and
//  Point-Free's `DependencyKey` but with stricter Sendable requirements and
//  a clear `live` / `preview` / `test` value trichotomy.
//

import Foundation

/// A key shape used in test/preview contexts only.
///
/// Interface modules can declare a `TestDependencyKey` for a service whose
/// live implementation lives in a separate module — the live module then
/// conforms the same key to ``DependencyKey``.
///
/// Splitting the protocols this way means feature interface modules never
/// need to import their `Live` package: tests and previews work against the
/// `testValue` / `previewValue` alone.
public protocol TestDependencyKey: Sendable {
    /// The type of value resolved for this key. Must be `Sendable` so that
    /// the value can cross isolation boundaries when read from a different
    /// task than the one that registered it.
    associatedtype Value: Sendable

    /// The default value used in tests. Most keys should set this to an
    /// `unimplemented` sentinel — a witness whose closures call
    /// `reportIssue(...)` and throw `DependencyError.unimplemented`. That
    /// surfaces unmocked calls as test failures instead of silently letting
    /// the test pass.
    static var testValue: Value { get }

    /// The default value used inside SwiftUI previews. Optional — defaults
    /// to ``testValue`` when not provided. Override to a deterministic,
    /// side-effect-free witness.
    static var previewValue: Value { get }
}

extension TestDependencyKey {
    /// Default: previews fall back to `testValue`.
    ///
    /// Test-aware previews surface missing previews loudly while ordinary
    /// live previews provide a custom `previewValue`.
    public static var previewValue: Value { Self.testValue }
}

/// A key whose live implementation is shipped alongside the protocol.
///
/// Used for keys defined in app or impl modules where the live value is
/// already available.
public protocol DependencyKey<Value>: TestDependencyKey {
    /// The production value. Lazily evaluated on first resolution.
    static var liveValue: Value { get }
}

extension DependencyKey {
    /// Default: tests fall back to the live value if `testValue` isn't
    /// overridden.
    ///
    /// Under an active test context (Swift Testing or XCTest) the fallback
    /// **reports an issue** before returning: silently running live
    /// implementations in tests is the classic trap this library exists to
    /// close — a test that "passes" against the network is worse than a
    /// loud one. Provide an explicit `testValue` (typically an
    /// `unimplemented` witness) or override the key in the test. A key
    /// whose live value is a pure value type (e.g. a `Calendar`) can keep
    /// the fallback and silence the report with `testValue = liveValue`
    /// spelled out.
    ///
    /// The report fires at most once per key per process — resolution
    /// results are cached.
    public static var testValue: Value {
        switch IssueContext.current {
            case .swiftTesting, .xctest:
                reportIssue(
                    "\(Self.self) has no testValue — tests are silently using its liveValue. "
                        + "Provide an explicit testValue (e.g. an unimplemented witness), override the "
                        + "key with withDependencies/.dependencies, or spell out testValue = liveValue "
                        + "if the live value is genuinely test-safe."
                )
            case .preview, .runtime:
                break
        }
        return Self.liveValue
    }
}
