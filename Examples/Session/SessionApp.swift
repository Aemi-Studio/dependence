//
//  SessionApp.swift
//  ExampleSessionApp
//
//  Demonstrates the `~Copyable` `ScopeToken` pattern: a generational scope
//  that begins at sign-in and ends at sign-out, with deterministic teardown
//  enforced by the type system.
//
//  This is the canonical answer to "post-login user dependencies":
//  - Pre-login: `User` is unavailable; reading it through a dependency would
//    fail loudly.
//  - At sign-in: a `SessionToken` is constructed with the authenticated user
//    and a teardown closure.
//  - During the session: code runs inside `session.enter { … }` and reads
//    `@Dependency(\.currentUser)` freely.
//  - At sign-out: the token is consumed; the compiler refuses any further use.
//

import Dependence
import Foundation

// MARK: - Per-session dependencies

public struct AuthenticatedUser: Sendable, Hashable {
    public let id: String
    public let displayName: String
}

/// A phantom tag distinguishing the session scope.
public enum SessionScope: ScopeTag {}

/// The slot is `Optional` so reading it before a session has been entered
/// produces a clear "nil current user" rather than a crash; the unimplemented
/// fallback is there to catch the misuse early in tests.
public enum CurrentUserKey: TestDependencyKey {
    public static var testValue: AuthenticatedUser? { nil }
}

extension DependencyValues {
    /// Manual accessor — `@DependencyEntry`'s no-init form derives the key
    /// name from the value type (`<TypeName>Key`), which doesn't apply
    /// cleanly to an `Optional<AuthenticatedUser>`. The hand-written form
    /// remains a first-class option whenever the convention doesn't fit.
    public var currentUser: AuthenticatedUser? {
        get { self[test: CurrentUserKey.self] }
        set { self[test: CurrentUserKey.self] = newValue }
    }
}

// MARK: - Session lifecycle

@main
enum SessionApp {
    static func main() async {
        // 1. Pre-login: `currentUser` is nil.
        withDependencies {
            // Default — no override needed.
            _ = $0
        } operation: {
            print("Pre-login: currentUser =", DependencyValues.current.currentUser as Any)
        }

        // 2. Sign in: build a generational token. The token cannot be copied
        //    or used after `enter` returns.
        let user = AuthenticatedUser(id: "ada-42", displayName: "Ada Lovelace")
        let session = ScopeToken<SessionScope, AuthenticatedUser>(
            value: user,
            teardown: { print("Session torn down") }
        )

        // 3. Run the authenticated shell inside `session.enter { … }`.
        await session.enter { (borrowedSession: borrowing ScopeToken<SessionScope, AuthenticatedUser>) async in
            // Bind the scoped value into the active DependencyValues so any
            // descendant code can read it via `@Dependency(\.currentUser)`.
            let snapshot = borrowedSession.snapshot()
            await withDependencies {
                $0.currentUser = snapshot
            } operation: {
                await runAuthenticatedShell()
            }
        }

        // 4. After `enter` returns, `session` is consumed. The next line
        //    would not compile:
        //
        //        session.enter { _ in }
        //        // error: 'session' used after consume
    }

    @Sendable
    static func runAuthenticatedShell() async {
        @Dependency(\.currentUser) var user
        if let user {
            print("Authenticated as \(user.displayName) (\(user.id))")
        } else {
            print("BUG: shell entered without a user")
        }
    }
}
