//
//  FeedClient+Live.swift
//  FeedImpl
//
//  The live `FeedClient` depends on the `AuthClient` interface — Feed needs
//  to know which user is signed in. It does NOT depend on `AuthImpl`: the
//  composition root supplies the live `AuthClient`.
//

import AuthInterface
import Dependence
import FeedInterface
import Foundation

extension FeedClient {
    public static var live: FeedClient {
        FeedClient(
            fetch: { userID in
                // Pretend network call.
                try await Task.sleep(for: .milliseconds(20))
                return (0..<5).map { i in
                    FeedItem(id: "\(userID)-\(i)", title: "Item #\(i) for \(userID)")
                }
            }
        )
    }
}

extension FeedClientKey: DependencyKey {
    public static var liveValue: FeedClient { .live }
}
