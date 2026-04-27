//
//  APIClient.swift
//  ExampleSmallApp
//
//  A toy witness — a struct of `@Sendable` closures — together with the live
//  / preview / test variants and a `DependencyValues` extension declared via
//  the `@DependencyEntry` macro.
//

import Dependence
import DependenceMacros
import Foundation

/// Minimal HTTP client witness: a struct of closures so it composes cleanly
/// with `withDependencies` overrides without requiring open inheritance.
@DependencyClient
public struct APIClient: Sendable {
    public var fetchGreeting: @Sendable () async throws -> String
}

extension APIClient {
    /// The production implementation. Pretends to talk to a server.
    public static let live = APIClient(
        fetchGreeting: {
            try await Task.sleep(for: .milliseconds(50))
            return "hello, world"
        }
    )

    /// A deterministic preview value.
    public static let preview = APIClient(
        fetchGreeting: { "hello from previews" }
    )
}

extension DependencyValues {
    /// The shared `APIClient` registered via the `@DependencyEntry` macro.
    /// Read with `@Dependency(\.apiClient)`; override with
    /// `withDependencies { $0.apiClient = .preview } operation: { … }`.
    @DependencyEntry(preview: APIClient.preview) public var apiClient = APIClient.live
}
