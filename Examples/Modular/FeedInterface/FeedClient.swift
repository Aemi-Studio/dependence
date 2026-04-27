//
//  FeedClient.swift
//  FeedInterface
//

import Dependence
import DependenceMacros

public struct FeedItem: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@DependencyClient
public struct FeedClient: Sendable {
    public var fetch: @Sendable (_ userID: String) async throws -> [FeedItem]
}

extension FeedClient {
    public static let preview = FeedClient(
        fetch: { _ in
            (0..<3).map { FeedItem(id: "p-\($0)", title: "Preview item #\($0)") }
        }
    )
}

public enum FeedClientKey: TestDependencyKey {
    public static var testValue: FeedClient { .unimplemented }
    public static var previewValue: FeedClient { .preview }
}

extension DependencyValues {
    @DependencyEntry public var feedClient: FeedClient
}
