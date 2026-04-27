//
//  ScopeToken.swift
//  Dependence
//
//  Generational, single-use scope tokens. The compiler enforces that a
//  `ScopeToken` is consumed exactly once and that copies cannot be made.
//  This is the canonical answer to "post-login user" / "per-request cache" /
//  "document scope" — values that exist only between a defined begin and
//  end, with deterministic teardown.
//

import Foundation

/// A phantom type marking a scope dimension. Used to constrain
/// ``ScopeToken`` to a particular kind of scope at compile time so that, for
/// example, a "request" token can never be passed where a "session" token is
/// expected.
public protocol ScopeTag: Sendable {}

/// A consume-once token that brackets a generational scope.
///
/// `ScopeToken` is `~Copyable`: the compiler refuses to make a copy. It
/// must be passed by `consuming` (transferring ownership) or `borrowing`
/// (read-only loan). After it's consumed by ``enter(operation:)`` or
/// ``close()``, any subsequent use is a `noncopyable_use_after_consume`
/// compiler error.
///
/// ```swift
/// let session = ScopeToken<SessionScope>(authenticatedUser: user) {
///     // Teardown closure — runs when the scope exits.
///     Task { await SessionLogger.flush() }
/// }
///
/// try await session.enter { borrowing scope in
///     try await withDependencies({ $0.session = scope.snapshot }) {
///         try await runAuthenticatedAppShell()
///     }
/// }
/// // `session` is consumed; using it here is a compile error.
/// ```
public struct ScopeToken<Tag: ScopeTag, Value: Sendable>: ~Copyable, Sendable {
    /// The value bound to this scope. Read-only after construction.
    public let value: Value

    private let teardown: @Sendable () -> Void

    /// Construct a token with a value and a teardown closure that runs when
    /// the scope exits (either normally via `enter` or by manual `close`).
    public init(
        value: Value,
        teardown: @escaping @Sendable () -> Void = {}
    ) {
        self.value = value
        self.teardown = teardown
    }

    /// Read-only snapshot of the token. Useful for binding the inner value
    /// onto a `DependencyValues` slot without consuming the token.
    public borrowing func snapshot() -> Value { value }

    /// Enter the scope, run `operation`, and tear down.
    ///
    /// The token is `consuming` here — the caller cannot use it again after
    /// this returns.
    @discardableResult
    public consuming func enter<R, E: Error>(
        operation: (borrowing ScopeToken<Tag, Value>) throws(E) -> R
    ) throws(E) -> R {
        // `defer` runs `teardown()` whether `operation` returns or throws,
        // delivering the deterministic-teardown contract documented above.
        // `operation` borrows `self`, so `self` (and therefore `teardown`)
        // remains live through the `defer` block.
        let teardown = self.teardown
        defer { teardown() }
        return try operation(self)
    }

    /// Async form.
    @discardableResult
    public consuming func enter<R: Sendable, E: Error>(
        isolation: isolated (any Actor)? = #isolation,
        operation: (borrowing ScopeToken<Tag, Value>) async throws(E) -> R
    ) async throws(E) -> R {
        let teardown = self.teardown
        defer { teardown() }
        return try await operation(self)
    }

    /// Close the scope explicitly. Invalidates the token.
    public consuming func close() {
        teardown()
    }
}
