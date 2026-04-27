//
//  UncheckedSendable.swift
//  Dependence
//
//  Internal helper for transferring values that are conceptually immutable
//  (e.g. `KeyPath`) through `@Sendable` closures. The Swift 6 standard
//  library does not give `KeyPath` an unconditional `Sendable` conformance —
//  it is a generic class — but reading a value through a key path is a pure
//  function of immutable data. We wrap such values in this box and accept the
//  unchecked conformance for ergonomic call sites.
//

import Foundation

/// Wraps a value in an `@unchecked Sendable` box.
///
/// Use only for values that are *conceptually immutable* (key paths,
/// metatypes, frozen structs that the type system fails to recognize as
/// Sendable). Misuse defeats the strict-concurrency model.
@usableFromInline
package struct UncheckedSendable<Value>: @unchecked Sendable {
    @usableFromInline
    let value: Value

    @inlinable
    package init(_ value: Value) {
        self.value = value
    }
}
