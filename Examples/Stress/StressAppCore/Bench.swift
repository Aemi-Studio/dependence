//
//  Bench.swift
//  ExampleStressAppCore
//
//  Headless benchmark routines used by the executable shell to drive
//  start-up, resolution, override and graph-walk measurements.
//

import Dependence
import Foundation

public enum StressBench {
    public struct Stats: Sendable {
        public let label: String
        public let iterations: Int
        public let totalNanos: UInt64
        public var nanosPerOp: Double { Double(totalNanos) / Double(iterations) }
        public var opsPerSecond: Double { 1_000_000_000.0 / nanosPerOp }
    }

    /// Warm cache, then resolve all 20 keys `iterations` times and time it.
    /// Exercises the cached read path through `DependencyValues.subscript`.
    public static func resolveAllKeys(iterations: Int) -> Stats {
        let v = DependencyValues.current
        // Warm the lazy cache for every key.
        _ = v.authHTTPClient; _ = v.feedHTTPClient; _ = v.profileHTTPClient
        _ = v.mediaHTTPClient; _ = v.searchHTTPClient; _ = v.analyticsHTTPClient
        _ = v.notificationHTTPClient; _ = v.syncHTTPClient
        _ = v.authService; _ = v.feedService; _ = v.profileService
        _ = v.mediaService; _ = v.searchService; _ = v.analyticsService
        _ = v.notificationService; _ = v.syncService; _ = v.cacheService
        _ = v.loggerService; _ = v.featureFlagService; _ = v.sessionService

        let start = DispatchTime.now()
        var sink: Int = 0
        for _ in 0..<iterations {
            sink &+= MemoryLayout.size(ofValue: v.authHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.feedHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.profileHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.mediaHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.searchHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.analyticsHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.notificationHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.syncHTTPClient)
            sink &+= MemoryLayout.size(ofValue: v.authService)
            sink &+= MemoryLayout.size(ofValue: v.feedService)
            sink &+= MemoryLayout.size(ofValue: v.profileService)
            sink &+= MemoryLayout.size(ofValue: v.mediaService)
            sink &+= MemoryLayout.size(ofValue: v.searchService)
            sink &+= MemoryLayout.size(ofValue: v.analyticsService)
            sink &+= MemoryLayout.size(ofValue: v.notificationService)
            sink &+= MemoryLayout.size(ofValue: v.syncService)
            sink &+= MemoryLayout.size(ofValue: v.cacheService)
            sink &+= MemoryLayout.size(ofValue: v.loggerService)
            sink &+= MemoryLayout.size(ofValue: v.featureFlagService)
            sink &+= MemoryLayout.size(ofValue: v.sessionService)
        }
        let end = DispatchTime.now()
        // Defeat dead-code-elimination on `sink`.
        precondition(sink >= 0)
        return Stats(
            label: "resolve-all-keys",
            iterations: iterations * 20,
            totalNanos: end.uptimeNanoseconds - start.uptimeNanoseconds
        )
    }

    /// Stress the override path: nested `withDependencies` blocks.
    public static func nestedOverrides(iterations: Int) -> Stats {
        let start = DispatchTime.now()
        var sink: Int = 0
        for _ in 0..<iterations {
            withDependencies {
                $0.featureFlagService = FeatureFlagService(
                    isEnabled: { _ in false },
                    variant: { _ in "override-1" }
                )
            } operation: {
                withDependencies {
                    $0.loggerService = LoggerService(log: { _ in })
                } operation: {
                    sink &+= DependencyValues.current.featureFlagService.isEnabled("x") ? 1 : 0
                }
            }
        }
        let end = DispatchTime.now()
        precondition(sink == 0)
        return Stats(
            label: "nested-overrides",
            iterations: iterations,
            totalNanos: end.uptimeNanoseconds - start.uptimeNanoseconds
        )
    }

    /// End-to-end async graph walk through the view-model's `refresh()` path.
    @MainActor
    public static func graphWalk(iterations: Int) async -> Stats {
        let model = StressViewModel()
        // Warm everything once.
        await model.refresh()
        let start = DispatchTime.now()
        for _ in 0..<iterations { await model.refresh() }
        let end = DispatchTime.now()
        return Stats(
            label: "graph-walk",
            iterations: iterations,
            totalNanos: end.uptimeNanoseconds - start.uptimeNanoseconds
        )
    }

    /// Print a single stats record in a stable shape for shell parsing.
    public static func print(_ stats: Stats) {
        let nsPerOp = String(format: "%.1f", stats.nanosPerOp)
        let mOps = String(format: "%.2f", stats.opsPerSecond / 1_000_000)
        Swift.print("[\(stats.label)] ops=\(stats.iterations) total=\(stats.totalNanos)ns ns/op=\(nsPerOp) Mops/s=\(mOps)")
    }
}
