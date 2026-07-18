//
//  DependenciesTrait.swift
//  DependenceTesting
//
//  A Swift Testing trait that scopes dependency overrides to a test or suite.
//

import Dependence
import Testing

/// A Swift Testing trait that applies dependency overrides for the wrapped
/// test or suite.
///
/// ```swift
/// @Suite(.dependencies { $0.uuid = .incrementing })
/// struct UserFlow {
///     @Test func login() async throws { … }
///
///     @Test(.dependencies { $0.apiClient = .mock })
///     func errorPath() async throws { … }
/// }
/// ```
///
/// Conforms to `TestScoping` so the override is applied across the entire
/// test (including any `async` work that branches off via `async let` /
/// `withTaskGroup`). The override is *additive* over any enclosing trait —
/// inner mutations win on conflict.
public struct DependenciesTrait: TestTrait, SuiteTrait, TestScoping {
    public let isRecursive: Bool = true

    @usableFromInline
    let mutate: @Sendable (inout DependencyValues) -> Void

    @usableFromInline
    init(_ mutate: @escaping @Sendable (inout DependencyValues) -> Void) {
        // Force-touch the bootstrap so `reportIssue(_:)` calls made from
        // inside the wrapped test surface as Swift Testing failures.
        _ = Bootstrap.once
        self.mutate = mutate
    }

    @concurrent
    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        try await withDependencies {
            mutate(&$0)
        } operation: {
            try await function()
        }
    }
}

extension Trait where Self == DependenciesTrait {
    /// Apply dependency overrides for the wrapped test or suite.
    ///
    /// ```swift
    /// @Test(.dependencies { $0.apiClient = .mock })
    /// func t() async { … }
    /// ```
    public static func dependencies(
        _ mutate: @escaping @Sendable (inout DependencyValues) -> Void
    ) -> DependenciesTrait {
        DependenciesTrait(mutate)
    }
}
