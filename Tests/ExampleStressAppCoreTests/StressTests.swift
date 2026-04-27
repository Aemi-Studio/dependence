//
//  StressTests.swift
//  ExampleStressAppCoreTests
//
//  End-to-end exercise of the wide stress example registry. These tests
//  intentionally walk every key, every override path, and the @Dependencies
//  macro-driven view-model so a regression anywhere in registration, caching,
//  override propagation, or task-local scoping shows up here first.
//

import Dependence
import DependenceTesting
@testable import ExampleStressAppCore
import Foundation
import Testing

// MARK: - Resolution coverage

@Suite("Stress: registry resolution")
struct StressRegistryTests {
    @Test("Every registered key resolves to its testValue under a Suite-level trait",
          .dependencies { _ in })
    func everyKeyResolves() {
        let v = DependencyValues.current
        // Under Swift Testing the resolver returns `testValue`, which the
        // registry doesn't override — so each one falls back to the
        // unimplemented witness from `@DependencyClient`. Just touching them
        // proves the keys are wired into the values bag without raising.
        // Reading via key paths exercises the macro-generated subscripts.
        _ = v.authHTTPClient
        _ = v.feedHTTPClient
        _ = v.profileHTTPClient
        _ = v.mediaHTTPClient
        _ = v.searchHTTPClient
        _ = v.analyticsHTTPClient
        _ = v.notificationHTTPClient
        _ = v.syncHTTPClient

        _ = v.authService
        _ = v.feedService
        _ = v.profileService
        _ = v.mediaService
        _ = v.searchService
        _ = v.analyticsService
        _ = v.notificationService
        _ = v.syncService
        _ = v.cacheService
        _ = v.loggerService
        _ = v.featureFlagService
        _ = v.sessionService
    }
}

// MARK: - Override propagation through the live witness graph

@Suite("Stress: override propagation")
struct StressOverrideTests {
    @Test("withDependencies override is visible through a multi-hop service")
    func multiHopOverride() async throws {
        try await withDependencies {
            // Override a leaf HTTP client; the live `SearchService.live` reads
            // it lazily through `deps()`, so the override must propagate
            // through two hops (service → HTTP client) at call time.
            $0.searchHTTPClient = SearchHTTPClient(
                query: { _ in ["unit-test-hit-1", "unit-test-hit-2"] },
                suggestions: { _ in [] }
            )
            // We need a session token for the auth.signIn → session.beginSession
            // hop to succeed.
            $0.authHTTPClient = .preview
            $0.analyticsHTTPClient = .preview
        } operation: {
            // Use the live witnesses for the services themselves so the
            // override has somewhere to flow through.
            try await withDependencies {
                $0.searchService = .live
                $0.authService = .live
            } operation: {
                let hits = try await DependencyValues.current.searchService.search("ignored")
                #expect(hits == ["unit-test-hit-1", "unit-test-hit-2"])
            }
        }
    }

    @Test("Nested withDependencies blocks compose, inner shadows outer")
    func nestedOverridesShadow() {
        withDependencies {
            $0.featureFlagService = FeatureFlagService(
                isEnabled: { _ in false },
                variant: { _ in "outer" }
            )
        } operation: {
            #expect(DependencyValues.current.featureFlagService.variant("x") == "outer")
            withDependencies {
                $0.featureFlagService = FeatureFlagService(
                    isEnabled: { _ in true },
                    variant: { _ in "inner" }
                )
            } operation: {
                #expect(DependencyValues.current.featureFlagService.isEnabled("x") == true)
                #expect(DependencyValues.current.featureFlagService.variant("x") == "inner")
            }
            // Outer scope is intact after the inner block exits.
            #expect(DependencyValues.current.featureFlagService.variant("x") == "outer")
        }
    }
}

// MARK: - View-model end-to-end

@Suite("Stress: view-model graph walk")
struct StressViewModelTests {
    @Test("refresh() drives every dependency under preview witnesses")
    @MainActor
    func refreshHydratesEveryField() async {
        await withDependencies {
            // Wire every key to its preview witness so the entire walk is
            // deterministic and never hits the unimplemented placeholders.
            $0.authHTTPClient = .preview
            $0.feedHTTPClient = .preview
            $0.profileHTTPClient = .preview
            $0.mediaHTTPClient = .preview
            $0.searchHTTPClient = .preview
            $0.analyticsHTTPClient = .preview
            $0.notificationHTTPClient = .preview
            $0.syncHTTPClient = .preview

            $0.authService = .preview
            $0.feedService = .preview
            $0.profileService = .preview
            $0.mediaService = .preview
            $0.searchService = .preview
            $0.analyticsService = .preview
            $0.notificationService = .preview
            $0.syncService = .preview
            $0.cacheService = .preview
            $0.loggerService = .preview
            $0.featureFlagService = .preview
            $0.sessionService = .preview
        } operation: {
            let model = StressViewModel()
            await model.refresh()
            #expect(model.status == "ok")
            #expect(model.refreshCount == 1)
            #expect(model.profileName == "Preview User")
            #expect(model.searchHits == ["preview-result"])
            #expect(model.feed.count == 3)
            #expect(model.lastError == nil)
        }
    }

    @Test("refresh() reports an error string when an upstream service throws")
    @MainActor
    func refreshSurfacesErrors() async {
        struct Boom: Error {}
        await withDependencies {
            $0.authService = AuthService(
                signIn: { _, _ in throw Boom() },
                signOut: { _ in },
                validate: { _ in true }
            )
        } operation: {
            let model = StressViewModel()
            await model.refresh()
            #expect(model.status == "error")
            #expect(model.refreshCount == 0)
            #expect(model.lastError != nil)
        }
    }
}

// MARK: - Bench harness sanity

@Suite("Stress: bench harness")
struct StressBenchTests {
    @Test("resolveAllKeys reports a non-zero op count and total time")
    func resolveBenchProducesNumbers() {
        let stats = StressBench.resolveAllKeys(iterations: 32)
        #expect(stats.iterations == 32 * 20)
        #expect(stats.totalNanos > 0)
        #expect(stats.nanosPerOp.isFinite)
        #expect(stats.opsPerSecond > 0)
    }

    @Test("nestedOverrides reports a non-zero op count and total time")
    func nestedBenchProducesNumbers() {
        let stats = StressBench.nestedOverrides(iterations: 32)
        #expect(stats.iterations == 32)
        #expect(stats.totalNanos > 0)
    }

    @MainActor
    @Test("graphWalk reports a non-zero op count and total time")
    func graphWalkBenchProducesNumbers() async {
        let stats = await withDependencies {
            $0.authHTTPClient = .preview
            $0.feedHTTPClient = .preview
            $0.profileHTTPClient = .preview
            $0.searchHTTPClient = .preview
            $0.analyticsHTTPClient = .preview
            $0.syncHTTPClient = .preview

            $0.authService = .preview
            $0.feedService = .preview
            $0.profileService = .preview
            $0.searchService = .preview
            $0.analyticsService = .preview
            $0.syncService = .preview
            $0.cacheService = .preview
            $0.featureFlagService = .preview
            $0.sessionService = .preview
        } operation: {
            await StressBench.graphWalk(iterations: 4)
        }
        #expect(stats.iterations == 4)
        #expect(stats.totalNanos > 0)
    }
}
