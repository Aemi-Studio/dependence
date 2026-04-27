//
//  DependencyKey.swift
//  Dependence
//
//  Identity types for dependencies. Mirrors SwiftUI's `EnvironmentKey` and
//  Point-Free's `DependencyKey` but with stricter Sendable requirements and
//  a clear `live` / `preview` / `test` value trichotomy.
//

import Foundation

/// A key shape used in test/preview contexts only. Interface modules can
/// declare a `TestDependencyKey` for a service whose live implementation
/// lives in a separate module — the live module then conforms the same key
/// to ``DependencyKey``.
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
    /// Default: previews fall back to `testValue`. Test-aware previews surface
    /// missing previews loudly while ordinary live previews provide a custom
    /// `previewValue`.
    public static var previewValue: Value { Self.testValue }
}

/// A key whose live implementation is shipped alongside the protocol. Used
/// for keys defined in app or impl modules where the live value is already
/// available.
public protocol DependencyKey<Value>: TestDependencyKey {
    /// The production value. Lazily evaluated on first resolution.
    static var liveValue: Value { get }
}

extension DependencyKey {
    /// Default: tests fall back to the live value if `testValue` isn't
    /// overridden. Most witnesses should override `testValue` with an
    /// unimplemented sentinel — but a key whose live value is already a
    /// pure value type (e.g. a `Calendar`) doesn't need to.
    public static var testValue: Value { Self.liveValue }
}
