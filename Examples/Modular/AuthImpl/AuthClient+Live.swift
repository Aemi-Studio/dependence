//
//  AuthClient+Live.swift
//  AuthImpl
//
//  Live implementation. Imported only by the composition root (or other
//  Impl modules that need a real AuthClient at the same level).
//

import AuthInterface
import Dependence
import Foundation
import Synchronization

extension AuthClient {
    public static var live: AuthClient {
        let storage = Mutex<String?>(nil)
        return AuthClient(
            currentUserID: { storage.withLock { $0 } },
            signIn: { email, _ in
                let id = "user-\(email.hashValue)"
                storage.withLock { $0 = id }
                return id
            },
            signOut: {
                storage.withLock { $0 = nil }
            }
        )
    }
}

/// Conform `AuthClientKey` to the full `DependencyKey` so apps wiring this
/// module get a real `liveValue`.
extension AuthClientKey: DependencyKey {
    public static var liveValue: AuthClient { .live }
}
