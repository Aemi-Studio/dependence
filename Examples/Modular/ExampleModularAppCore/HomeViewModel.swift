//
//  HomeViewModel.swift
//  ExampleModularAppCore
//

import AuthInterface
import Dependence
import DependenceMacros
import FeedInterface
import Foundation
import Observation
import ProfileInterface

@MainActor
@Observable
@Dependencies(\.authClient, \.feedClient, \.profileClient)
public final class HomeViewModel {
    public private(set) var userID: String?
    public private(set) var feed: [FeedItem] = []
    public private(set) var profile: ProfileSummary?
    public private(set) var error: String?

    public init() {}

    public func signIn() async {
        do {
            let id = try await authClient.signIn("ada@example.com", "hunter2")
            userID = id
            async let feedTask = feedClient.fetch(id)
            async let profileTask = profileClient.summary(id)
            feed = try await feedTask
            profile = try await profileTask
        } catch {
            self.error = String(describing: error)
        }
    }

    public func signOut() async {
        await authClient.signOut()
        userID = nil
        feed = []
        profile = nil
    }
}
