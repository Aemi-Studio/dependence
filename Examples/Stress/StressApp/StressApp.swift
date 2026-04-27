//
//  StressApp.swift
//  ExampleStressApp
//
//  Thin executable shell. The previewable UI lives in `ExampleStressAppCore`
//  so Xcode can host SwiftUI previews — executable targets demand
//  `ENABLE_DEBUG_DYLIB`, which SwiftPM does not expose.
//
//  When launched from a terminal with `--bench <name>`, the shell skips the
//  SwiftUI scene and runs a headless benchmark from `StressBench`. This is
//  what `Tools/stress-profile.sh` wires up to drive cold-start, resolution,
//  override and graph-walk numbers.
//
//      ExampleStressApp --bench resolve   --iterations 100000
//      ExampleStressApp --bench nested    --iterations 50000
//      ExampleStressApp --bench graph     --iterations 1000
//      ExampleStressApp --bench cold-start
//

import Dependence
import ExampleStressAppCore
import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Headless entry

/// Runs a single benchmark and prints one stable-shape line per result.
///
/// Not isolated to `@MainActor`: when this is called from a detached task it
/// must keep running on the cooperative pool, because the main thread is
/// parked on a `DispatchSemaphore` waiting for it to finish. The few
/// MainActor-bound bits (the `graphWalk` benchmark) hop explicitly via
/// `MainActor.run`.
private func runBench(_ name: String, iterations: Int) async {
    switch name {
    case "resolve":
        StressBench.print(StressBench.resolveAllKeys(iterations: iterations))
    case "nested":
        StressBench.print(StressBench.nestedOverrides(iterations: iterations))
    case "graph":
        StressBench.print(await StressBench.graphWalk(iterations: iterations))
    case "all":
        StressBench.print(StressBench.resolveAllKeys(iterations: iterations))
        StressBench.print(StressBench.nestedOverrides(iterations: iterations))
        StressBench.print(await StressBench.graphWalk(iterations: max(1, iterations / 100)))
    case "cold-start":
        // The work is the launch itself — emit a marker so the wrapping shell
        // script can confirm we got past `main`.
        Swift.print("[cold-start] alive pid=\(ProcessInfo.processInfo.processIdentifier)")
    default:
        FileHandle.standardError.write(Data("unknown --bench \(name)\n".utf8))
        exit(64)
    }
}

/// Returns `(bench, iterations)` if the process was invoked with `--bench`.
private func parseBench(_ args: [String]) -> (String, Int)? {
    guard let i = args.firstIndex(of: "--bench"), i + 1 < args.count else { return nil }
    let name = args[i + 1]
    var iterations = 10_000
    if let j = args.firstIndex(of: "--iterations"), j + 1 < args.count,
       let parsed = Int(args[j + 1]) {
        iterations = parsed
    }
    return (name, iterations)
}

// MARK: - SwiftUI shell
//
// We can't use the implicit `@main` synthesis on a `App` here: when `--bench`
// is on the command line we need to skip the SwiftUI runloop entirely and
// run the headless harness on a fresh top-level Task. A custom `main()` lets
// us branch *before* SwiftUI's main thread is captured.

#if canImport(SwiftUI)
struct StressAppScene: App {
    var body: some Scene {
        WindowGroup {
            StressView()
        }
        // Composition root: declare the live dependency graph in one place.
        // The first body evaluation seeds the process-wide cache through
        // `prepareDependencies`, so every `@Dependency` read — including the
        // ones inside `@Observable` view models that SwiftUI never drives —
        // sees these values without any other call-site doing setup.
        .dependencies {
            $0.authHTTPClient = .live
            $0.feedHTTPClient = .live
            $0.profileHTTPClient = .live
            $0.mediaHTTPClient = .live
            $0.searchHTTPClient = .live
            $0.analyticsHTTPClient = .live
            $0.notificationHTTPClient = .live
            $0.syncHTTPClient = .live

            $0.authService = .live
            $0.feedService = .live
            $0.profileService = .live
            $0.mediaService = .live
            $0.searchService = .live
            $0.analyticsService = .live
            $0.notificationService = .live
            $0.syncService = .live
            $0.cacheService = .live
            $0.loggerService = .live
            $0.featureFlagService = .live
            $0.sessionService = .live
        }
    }
}

@main
enum StressApp {
    static func main() {
        if let (name, iterations) = parseBench(CommandLine.arguments) {
            // Headless: spawn the work on the cooperative pool, then enter
            // `dispatchMain()` so the main thread pumps GCD. That lets
            // `MainActor`-isolated work — e.g. the `StressViewModel` graph
            // walk — actually schedule. The detached task `exit(0)`s itself.
            Task.detached(priority: .userInitiated) {
                await runBench(name, iterations: iterations)
                exit(0)
            }
            dispatchMain() // never returns
        }
        StressAppScene.main()
    }
}
#else
@main
enum StressApp {
    static func main() async {
        let args = CommandLine.arguments
        let (name, iterations) = parseBench(args) ?? ("all", 10_000)
        await runBench(name, iterations: iterations)
    }
}
#endif
