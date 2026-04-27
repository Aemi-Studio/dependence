//
//  FeedClient+Fake.swift
//  FeedTestSupport
//

import FeedInterface

extension FeedClient {
    public static func returning(_ items: [FeedItem]) -> FeedClient {
        FeedClient(fetch: { _ in items })
    }

    public static func failing(_ error: any Error) -> FeedClient {
        FeedClient(fetch: { _ in throw error })
    }
}
