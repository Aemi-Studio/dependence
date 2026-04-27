//
//  AuthClient+Fake.swift
//  AuthTestSupport
//
//  Fakes for tests. Lives in its own target so production targets never
//  link a test-only implementation.
//

import AuthInterface

extension AuthClient {
    /// A successful sign-in fake: every credential is accepted.
    public static func acceptAll(userID: String = "test-user") -> AuthClient {
        AuthClient(
            currentUserID: { userID },
            signIn: { _, _ in userID },
            signOut: {}
        )
    }

    /// A failing sign-in fake.
    public static func rejectAll(error: any Error) -> AuthClient {
        AuthClient(
            currentUserID: { nil },
            signIn: { _, _ in throw error },
            signOut: {}
        )
    }
}
