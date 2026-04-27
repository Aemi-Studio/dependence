//
//  ProfileClient+Live.swift
//  ProfileImpl
//

import AuthInterface
import Dependence
import Foundation
import ProfileInterface

extension ProfileClient {
    public static var live: ProfileClient {
        ProfileClient(
            summary: { userID in
                try await Task.sleep(for: .milliseconds(15))
                return ProfileSummary(
                    displayName: "User \(userID.suffix(4))",
                    bio: "Live profile bio for \(userID)"
                )
            }
        )
    }
}

extension ProfileClientKey: DependencyKey {
    public static var liveValue: ProfileClient { .live }
}
