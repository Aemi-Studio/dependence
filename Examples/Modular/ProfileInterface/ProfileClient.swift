//
//  ProfileClient.swift
//  ProfileInterface
//

import Dependence
import DependenceMacros

public struct ProfileSummary: Sendable, Hashable {
    public var displayName: String
    public var bio: String
    public init(displayName: String, bio: String) {
        self.displayName = displayName
        self.bio = bio
    }
}

@DependencyClient
public struct ProfileClient: Sendable {
    public var summary: @Sendable (_ userID: String) async throws -> ProfileSummary
}

extension ProfileClient {
    public static let preview = ProfileClient(
        summary: { _ in ProfileSummary(displayName: "Ada", bio: "Preview bio") }
    )
}

public enum ProfileClientKey: TestDependencyKey {
    public static var testValue: ProfileClient { .unimplemented }
    public static var previewValue: ProfileClient { .preview }
}

extension DependencyValues {
    @DependencyEntry public var profileClient: ProfileClient
}
