//
//  StressViewModel.swift
//  ExampleStressAppCore
//
//  Pulls in 11 services through a single `@Dependencies(...)` macro
//  invocation and exercises a representative subset on each `refresh()`.
//

import Dependence
import DependenceMacros
import Foundation
import Observation

@MainActor
@Observable
@Dependencies(
    \.authService,
    \.feedService,
    \.profileService,
    \.mediaService,
    \.searchService,
    \.analyticsService,
    \.notificationService,
    \.syncService,
    \.cacheService,
    \.featureFlagService,
    \.sessionService
)
public final class StressViewModel {
    public private(set) var status: String = "idle"
    public private(set) var feed: [FeedItem] = []
    public private(set) var profileName: String = "—"
    public private(set) var searchHits: [String] = []
    public private(set) var refreshCount: Int = 0
    public private(set) var lastError: String?

    public init() {}

    /// Walks ~10 dependency reads end-to-end on every call.
    public func refresh() async {
        do {
            status = "signing in"
            let token = try await authService.signIn("alice", "hunter2")
            status = "loading"
            async let feedTask = feedService.loadFirstPage()
            async let profileTask = profileService.current()
            async let searchTask = searchService.search("dependence")
            let (loadedFeed, profile, hits) = try await (feedTask, profileTask, searchTask)
            self.feed = loadedFeed
            self.profileName = profile.displayName
            self.searchHits = hits
            try await analyticsService.track("stress.refresh", ["count": String(refreshCount + 1)])
            _ = try await syncService.push(["last-refresh"])
            _ = featureFlagService.isEnabled("stress.enable")
            await cacheService.set("stress.last-token", Data(token.utf8))
            try await authService.signOut(token)
            self.refreshCount += 1
            self.status = "ok"
            self.lastError = nil
        } catch {
            self.status = "error"
            self.lastError = String(describing: error)
        }
    }
}
