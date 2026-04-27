//
//  ProfileClient+Fake.swift
//  ProfileTestSupport
//

import ProfileInterface

extension ProfileClient {
    public static func returning(_ summary: ProfileSummary) -> ProfileClient {
        ProfileClient(summary: { _ in summary })
    }
}
