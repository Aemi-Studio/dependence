//
//  Registration.swift
//  ExampleStressAppCore
//
//  Registers all 20 dependencies on `DependencyValues` via `@DependencyEntry`.
//  This is the API surface the rest of the app reads through
//  `@Dependency(\.feedService)` etc.
//
//  Two scopes for installing values:
//
//  - **Composition root** — `Scene.dependencies(StressLive)` in `StressApp.swift`.
//    Seeds the process-wide cache via `prepareDependencies`, so every read
//    (including ones inside `@Observable` view models) sees the live values
//    without any further setup at the call site.
//
//  - **Subtree (previews, A/B, tests)** — `View.dependencies(StressPreview)`
//    on a single view. Subtree overrides flow through both the SwiftUI
//    environment and the process-wide subtree cell, so non-View hosts pick
//    them up too.
//
//  Each entry passes `liveValue` (the default expression), `previewValue`
//  (via `preview:`) and `testValue` (via `test:`) at registration time. The
//  macro stamps all three directly into the generated `__Key_<name>`
//  conformance, so generic `K.previewValue`/`K.testValue` dispatch finds
//  them — no separate wiring closure, no extension-trick, no `#Preview`
//  modifier required:
//
//      #Preview { StressView() }   // auto-resolves to .preview witnesses
//
//  The explicit `test:` witnesses matter: without them `testValue` falls
//  back to `liveValue`, and (as of the fail-closed reporting change) that
//  fallback reports an issue under Swift Testing/XCTest — the registry
//  demonstrates the recommended shape: tests hit `unimplemented` sentinels
//  unless they override what they use.
//

import Dependence
import DependenceMacros
import Foundation

extension DependencyValues {
    // MARK: HTTP clients
    @DependencyEntry(preview: AuthHTTPClient.preview, test: AuthHTTPClient.testWitness) public var authHTTPClient:
        AuthHTTPClient = .live
    @DependencyEntry(preview: FeedHTTPClient.preview, test: FeedHTTPClient.testWitness) public var feedHTTPClient:
        FeedHTTPClient = .live
    @DependencyEntry(preview: ProfileHTTPClient.preview, test: ProfileHTTPClient.testWitness) public
        var profileHTTPClient: ProfileHTTPClient = .live
    @DependencyEntry(preview: MediaHTTPClient.preview, test: MediaHTTPClient.testWitness) public var mediaHTTPClient:
        MediaHTTPClient = .live
    @DependencyEntry(preview: SearchHTTPClient.preview, test: SearchHTTPClient.testWitness) public var searchHTTPClient:
        SearchHTTPClient = .live
    @DependencyEntry(preview: AnalyticsHTTPClient.preview, test: AnalyticsHTTPClient.testWitness) public
        var analyticsHTTPClient: AnalyticsHTTPClient = .live
    @DependencyEntry(preview: NotificationHTTPClient.preview, test: NotificationHTTPClient.testWitness) public
        var notificationHTTPClient: NotificationHTTPClient = .live
    @DependencyEntry(preview: SyncHTTPClient.preview, test: SyncHTTPClient.testWitness) public var syncHTTPClient:
        SyncHTTPClient = .live

    // MARK: Services
    @DependencyEntry(preview: AuthService.preview, test: AuthService.testWitness) public var authService: AuthService =
        .live
    @DependencyEntry(preview: FeedService.preview, test: FeedService.testWitness) public var feedService: FeedService =
        .live
    @DependencyEntry(preview: ProfileService.preview, test: ProfileService.testWitness) public var profileService:
        ProfileService = .live
    @DependencyEntry(preview: MediaService.preview, test: MediaService.testWitness) public var mediaService:
        MediaService = .live
    @DependencyEntry(preview: SearchService.preview, test: SearchService.testWitness) public var searchService:
        SearchService = .live
    @DependencyEntry(preview: AnalyticsService.preview, test: AnalyticsService.testWitness) public var analyticsService:
        AnalyticsService = .live
    @DependencyEntry(preview: NotificationService.preview, test: NotificationService.testWitness) public
        var notificationService: NotificationService = .live
    @DependencyEntry(preview: SyncService.preview, test: SyncService.testWitness) public var syncService: SyncService =
        .live
    @DependencyEntry(preview: CacheService.preview, test: CacheService.testWitness) public var cacheService:
        CacheService = .live
    @DependencyEntry(preview: LoggerService.preview, test: LoggerService.testWitness) public var loggerService:
        LoggerService = .live
    @DependencyEntry(preview: FeatureFlagService.preview, test: FeatureFlagService.testWitness) public
        var featureFlagService: FeatureFlagService = .live
    @DependencyEntry(preview: SessionService.preview, test: SessionService.testWitness) public var sessionService:
        SessionService = .live
}
