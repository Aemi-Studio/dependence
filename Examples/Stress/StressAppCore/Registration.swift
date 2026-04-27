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
//  Each entry passes both `liveValue` (the default expression) and
//  `previewValue` (via the `preview:` argument) at registration time. The
//  macro stamps both directly into the generated `__Key_<name>` conformance,
//  so generic `K.previewValue` dispatch finds them — no separate wiring
//  closure, no extension-trick, no `#Preview` modifier required:
//
//      #Preview { StressView() }   // auto-resolves to .preview witnesses
//

import Dependence
import DependenceMacros
import Foundation

extension DependencyValues {
    // MARK: HTTP clients
    @DependencyEntry(preview: AuthHTTPClient.preview)         public var authHTTPClient: AuthHTTPClient = .live
    @DependencyEntry(preview: FeedHTTPClient.preview)         public var feedHTTPClient: FeedHTTPClient = .live
    @DependencyEntry(preview: ProfileHTTPClient.preview)      public var profileHTTPClient: ProfileHTTPClient = .live
    @DependencyEntry(preview: MediaHTTPClient.preview)        public var mediaHTTPClient: MediaHTTPClient = .live
    @DependencyEntry(preview: SearchHTTPClient.preview)       public var searchHTTPClient: SearchHTTPClient = .live
    @DependencyEntry(preview: AnalyticsHTTPClient.preview)    public var analyticsHTTPClient: AnalyticsHTTPClient = .live
    @DependencyEntry(preview: NotificationHTTPClient.preview) public var notificationHTTPClient: NotificationHTTPClient = .live
    @DependencyEntry(preview: SyncHTTPClient.preview)         public var syncHTTPClient: SyncHTTPClient = .live

    // MARK: Services
    @DependencyEntry(preview: AuthService.preview)            public var authService: AuthService = .live
    @DependencyEntry(preview: FeedService.preview)            public var feedService: FeedService = .live
    @DependencyEntry(preview: ProfileService.preview)         public var profileService: ProfileService = .live
    @DependencyEntry(preview: MediaService.preview)           public var mediaService: MediaService = .live
    @DependencyEntry(preview: SearchService.preview)          public var searchService: SearchService = .live
    @DependencyEntry(preview: AnalyticsService.preview)       public var analyticsService: AnalyticsService = .live
    @DependencyEntry(preview: NotificationService.preview)    public var notificationService: NotificationService = .live
    @DependencyEntry(preview: SyncService.preview)            public var syncService: SyncService = .live
    @DependencyEntry(preview: CacheService.preview)           public var cacheService: CacheService = .live
    @DependencyEntry(preview: LoggerService.preview)          public var loggerService: LoggerService = .live
    @DependencyEntry(preview: FeatureFlagService.preview)     public var featureFlagService: FeatureFlagService = .live
    @DependencyEntry(preview: SessionService.preview)         public var sessionService: SessionService = .live
}
