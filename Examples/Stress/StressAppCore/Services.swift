//
//  Services.swift
//  ExampleStressAppCore
//
//  Twelve domain-service witnesses sitting on top of the HTTP clients.
//  Service `liveValue`s read other dependencies through
//  `DependencyValues._current` *at call time* — never at construction —
//  which both keeps the live-value graph free of init-time cycles and gives
//  the resolver a realistic workout: every service call walks 1–3 keys
//  through the lock + cache.
//

import Dependence
import DependenceMacros
import Foundation

@inline(__always)
private func deps() -> DependencyValues { DependencyValues.current }

// MARK: - Auth

@DependencyClient
public struct AuthService: Sendable {
    public var signIn: @Sendable (_ user: String, _ password: String) async throws -> String
    public var signOut: @Sendable (_ token: String) async throws -> Void
    public var validate: @Sendable (_ token: String) async throws -> Bool
}

extension AuthService {
    public static let live = AuthService(
        signIn: { user, pass in
            @Dependency(\.analyticsHTTPClient) var analytics
            @Dependency(\.authHTTPClient) var authHTTP
            @Dependency(\.sessionService) var session

            try await analytics.track("auth.signIn.attempt", ["user": user])
            let token = try await authHTTP.signIn(user, pass)
            await session.beginSession(token)
            return token
        },
        signOut: { token in
            try await deps().authHTTPClient.signOut(token)
            await deps().sessionService.endSession()
        },
        validate: { token in
            try await deps().authHTTPClient.validate(token)
        }
    )
    public static let preview = AuthService(
        signIn: { _, _ in "preview-token" },
        signOut: { _ in },
        validate: { _ in true }
    )
}

// MARK: - Feed

@DependencyClient
public struct FeedService: Sendable {
    public var loadFirstPage: @Sendable () async throws -> [FeedItem]
    public var loadNextPage: @Sendable (_ after: Int) async throws -> [FeedItem]
    public var like: @Sendable (_ id: Int) async throws -> Void
}

extension FeedService {
    public static let live = FeedService(
        loadFirstPage: {
            try await deps().analyticsHTTPClient.track("feed.load", [:])
            return try await deps().feedHTTPClient.page(0)
        },
        loadNextPage: { cursor in
            try await deps().feedHTTPClient.page(cursor + 1)
        },
        like: { id in
            try await deps().feedHTTPClient.like(id)
            try await deps().analyticsHTTPClient.track("feed.like", ["id": String(id)])
        }
    )
    public static let preview = FeedService(
        loadFirstPage: { (0..<3).map { FeedItem(id: $0, title: "preview-\($0)") } },
        loadNextPage: { _ in [] },
        like: { _ in }
    )
}

// MARK: - Profile

@DependencyClient
public struct ProfileService: Sendable {
    public var current: @Sendable () async throws -> UserProfile
    public var update: @Sendable (_ profile: UserProfile) async throws -> Void
}

extension ProfileService {
    public static let live = ProfileService(
        current: {
            let userID = try await deps().sessionService.currentUserID()
            return try await deps().profileHTTPClient.fetch(userID)
        },
        update: { profile in
            try await deps().profileHTTPClient.update(profile)
        }
    )
    public static let preview = ProfileService(
        current: { UserProfile(id: "preview-user", displayName: "Preview User") },
        update: { _ in }
    )
}

// MARK: - Media

@DependencyClient
public struct MediaService: Sendable {
    public var thumbnail: @Sendable (_ id: String) async throws -> Data
    public var upload: @Sendable (_ payload: Data) async throws -> String
}

extension MediaService {
    public static let live = MediaService(
        thumbnail: { id in try await deps().mediaHTTPClient.thumbnail(id) },
        upload: { data in try await deps().mediaHTTPClient.upload(data) }
    )
    public static let preview = MediaService(
        thumbnail: { _ in Data() },
        upload: { _ in "preview-asset" }
    )
}

// MARK: - Search

@DependencyClient
public struct SearchService: Sendable {
    public var search: @Sendable (_ term: String) async throws -> [String]
    public var suggest: @Sendable (_ prefix: String) async throws -> [String]
}

extension SearchService {
    public static let live = SearchService(
        search: { term in
            try await deps().analyticsHTTPClient.track("search.query", ["term": term])
            return try await deps().searchHTTPClient.query(term)
        },
        suggest: { prefix in try await deps().searchHTTPClient.suggestions(prefix) }
    )
    public static let preview = SearchService(
        search: { _ in ["preview-result"] },
        suggest: { _ in ["preview-suggestion"] }
    )
}

// MARK: - Analytics

@DependencyClient
public struct AnalyticsService: Sendable {
    public var track: @Sendable (_ event: String, _ properties: [String: String]) async throws -> Void
    public var flush: @Sendable () async throws -> Void
}

extension AnalyticsService {
    public static let live = AnalyticsService(
        track: { event, props in try await deps().analyticsHTTPClient.track(event, props) },
        flush: { try await deps().analyticsHTTPClient.flush() }
    )
    public static let preview = AnalyticsService(
        track: { _, _ in },
        flush: {}
    )
}

// MARK: - Notifications

@DependencyClient
public struct NotificationService: Sendable {
    public var register: @Sendable (_ deviceToken: String) async throws -> Void
    public var deregister: @Sendable (_ deviceToken: String) async throws -> Void
}

extension NotificationService {
    public static let live = NotificationService(
        register: { tok in try await deps().notificationHTTPClient.register(tok) },
        deregister: { tok in try await deps().notificationHTTPClient.deregister(tok) }
    )
    public static let preview = NotificationService(
        register: { _ in },
        deregister: { _ in }
    )
}

// MARK: - Sync

@DependencyClient
public struct SyncService: Sendable {
    public var pull: @Sendable (_ since: Date) async throws -> [String]
    public var push: @Sendable (_ payload: [String]) async throws -> Date
}

extension SyncService {
    public static let live = SyncService(
        pull: { date in try await deps().syncHTTPClient.pull(date) },
        push: { payload in try await deps().syncHTTPClient.push(payload) }
    )
    public static let preview = SyncService(
        pull: { _ in ["preview-delta"] },
        push: { _ in Date(timeIntervalSince1970: 0) }
    )
}

// MARK: - Cache

public actor CacheBox {
    private var storage: [String: Data] = [:]
    public init() {}
    public func get(_ key: String) -> Data? { storage[key] }
    public func set(_ key: String, _ value: Data) { storage[key] = value }
    public func clear() { storage.removeAll() }
}

@DependencyClient
public struct CacheService: Sendable {
    public var get: @Sendable (_ key: String) async -> Data?
    public var set: @Sendable (_ key: String, _ value: Data) async -> Void
    public var clear: @Sendable () async -> Void
}

extension CacheService {
    /// A live impl backed by a shared actor.
    public static let live: CacheService = {
        let box = CacheBox()
        return CacheService(
            get: { key in await box.get(key) },
            set: { key, value in await box.set(key, value) },
            clear: { await box.clear() }
        )
    }()

    public static let preview: CacheService = {
        let box = CacheBox()
        return CacheService(
            get: { key in await box.get(key) },
            set: { key, value in await box.set(key, value) },
            clear: { await box.clear() }
        )
    }()
}

// MARK: - Logger

@DependencyClient
public struct LoggerService: Sendable {
    public var log: @Sendable (_ message: String) -> Void
}

extension LoggerService {
    // The live logger swallows everything — benchmarks must not pay for IO.
    public static let live = LoggerService(log: { _ in })
    public static let preview = LoggerService(log: { _ in })
}

// MARK: - Feature flags

@DependencyClient
public struct FeatureFlagService: Sendable {
    public var isEnabled: @Sendable (_ name: String) -> Bool
    public var variant: @Sendable (_ name: String) -> String
}

extension FeatureFlagService {
    public static let live = FeatureFlagService(
        isEnabled: { _ in true },
        variant: { _ in "control" }
    )
    public static let preview = FeatureFlagService(
        isEnabled: { _ in true },
        variant: { _ in "preview" }
    )
}

// MARK: - Session (stateful)

public actor SessionBox {
    public private(set) var token: String?
    public init() {}
    public func setToken(_ value: String?) { token = value }
}

@DependencyClient
public struct SessionService: Sendable {
    public var beginSession: @Sendable (_ token: String) async -> Void
    public var endSession: @Sendable () async -> Void
    public var currentToken: @Sendable () async -> String?
    public var currentUserID: @Sendable () async throws -> String
}

extension SessionService {
    public static let live: SessionService = {
        let box = SessionBox()
        return SessionService(
            beginSession: { token in await box.setToken(token) },
            endSession: { await box.setToken(nil) },
            currentToken: { await box.token },
            currentUserID: {
                guard let token = await box.token else {
                    throw DependencyError.unimplemented("session.currentUserID without active token")
                }
                return "user-of-\(token)"
            }
        )
    }()

    public static let preview: SessionService = {
        let box = SessionBox()
        return SessionService(
            beginSession: { token in await box.setToken(token) },
            endSession: { await box.setToken(nil) },
            currentToken: { await box.token },
            currentUserID: { "preview-user" }
        )
    }()
}
