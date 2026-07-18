//
//  AuthClient.swift
//  AuthInterface
//
//  The interface module: defines the witness, the dependency slot, and the
//  preview/test fallbacks. Crucially, this module does NOT depend on the
//  live implementation — feature consumers can compile against the
//  interface alone.
//

import Dependence
import DependenceMacros

/// Authentication witness exposed to the rest of the app.
@DependencyClient
public struct AuthClient: Sendable {
    public var currentUserID: @Sendable () -> String?
    public var signIn: @Sendable (_ email: String, _ password: String) async throws -> String
    public var signOut: @Sendable () async -> Void
}

extension AuthClient {
    /// A safe deterministic preview value: returns a fixed user ID.
    public static let preview = AuthClient(
        currentUserID: { "preview-user" },
        signIn: { _, _ in "preview-user" },
        signOut: {}
    )
}

/// `TestDependencyKey` (interface-only) — the live implementation lives in
/// `AuthImpl` and conforms the same key to `DependencyKey` there.
public enum AuthClientKey: TestDependencyKey {
    public static var testValue: AuthClient { .unimplemented }
    public static var previewValue: AuthClient { .preview }
}

extension DependencyValues {
    /// Read with `@Dependency(\.authClient)`.
    ///
    /// The no-initializer form of
    /// `@DependencyEntry` routes through `AuthClientKey: TestDependencyKey`,
    /// so consumers don't need to import the live module.
    @DependencyEntry public var authClient: AuthClient
}
