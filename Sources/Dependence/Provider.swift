//
//  Provider.swift
//  Dependence
//

import Foundation

/// A deferred constructor for `Value`.
///
/// Produces a fresh value on each call.
///
/// Use `Provider` to break dependency cycles or to express "give me a new
/// instance each time" semantics inside a witness:
///
/// ```swift
/// struct AuthService: Sendable {
///     var newAttempt: @Sendable () -> LoginAttempt
/// }
/// ```
///
/// is equivalent to
///
/// ```swift
/// struct AuthService: Sendable {
///     var newAttempt: Provider<LoginAttempt>
/// }
/// ```
///
/// but reads more clearly when the intent is explicitly "factory of T".
public struct Provider<Value>: Sendable {
    @usableFromInline
    let make: @Sendable () -> Value

    public init(_ make: @escaping @Sendable () -> Value) {
        self.make = make
    }

    /// Produce a fresh value.
    @inlinable
    public func callAsFunction() -> Value { make() }
}

/// Async variant of ``Provider``.
public struct AsyncProvider<Value: Sendable>: Sendable {
    @usableFromInline
    let make: @Sendable () async throws -> Value

    public init(_ make: @escaping @Sendable () async throws -> Value) {
        self.make = make
    }

    @inlinable
    public func callAsFunction() async throws -> Value { try await make() }
}
