// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "dependence",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        // Core: Foundation-only base + conditional SwiftUI bridge.
        //
        // `.dynamic` so that an app embedding several feature frameworks that
        // all link Dependence shares ONE copy of the library — and therefore
        // one process-wide resolution cache, subtree stack, and issue-handler
        // registry. Static linking would duplicate that state per image and
        // silently split the container.
        .library(name: "Dependence", type: .dynamic, targets: ["Dependence"]),

        // Optional ergonomic macros. Importing this product pulls in SwiftSyntax.
        .library(name: "DependenceMacros", targets: ["DependenceMacros"]),

        // Swift Testing trait + TestClock/ImmediateClock/UnimplementedClock.
        //
        // `.dynamic` — the one satellite that MUST be, because it is the one
        // an app links into its **unit-test bundle**. As an automatic
        // (static) product, `DependenceTesting`'s archive re-embeds a second
        // full copy of the `Dependence` target (its target depends on the
        // core target). Linked into the test bundle, that static copy defines
        // the core *inside the bundle image*, so the test module's
        // `DependencyValues._current` / `withDependencies` references bind the
        // bundle-local copy instead of the app's `Dependence.framework`. A
        // `withDependencies { … }` override set from a test then never reaches
        // the container the app resolves against — the split that forced
        // consumers to route bindings through an app-image shim
        // (`withHostDependencies`). Shipping it dynamic keeps the core OUT of
        // the test-bundle image: the bundle imports `Dependence` two-level
        // (from the app), so test and app code share one `_current`.
        //
        // Only this satellite is dynamic. Under the SwiftBuild build system a
        // dynamic library product still *embeds* its whole target closure
        // (each satellite framework carries its own copy of the core rather
        // than linking `Dependence.framework`), so making the non-test
        // adapters dynamic would not de-duplicate the core — it would only
        // push a second core copy into the **shipping app** that links them
        // (duplicate Objective-C classes at launch, and a link-but-not-embed
        // hazard for a framework the app references without bundling). Because
        // `DependenceTesting` is only ever loaded by a test bundle, its
        // residual embedded copy stays confined to test runs. The UIKit /
        // AppKit / AppIntents adapters therefore stay automatic.
        .library(name: "DependenceTesting", type: .dynamic, targets: ["DependenceTesting"]),

        // UIKit adapter — UITraitDefinition + UIObservationTracking helpers.
        .library(name: "DependenceUIKit", targets: ["DependenceUIKit"]),

        // AppKit adapter — NSResponder chain + NSDocument helpers.
        .library(name: "DependenceAppKit", targets: ["DependenceAppKit"]),

        // App Intents bridge — AppDependencyManager <-> DependencyValues.
        .library(name: "DependenceAppIntents", targets: ["DependenceAppIntents"]),

        // Examples (executables — kept in-package so CI builds them).
        .executable(
            name: "ExampleSmallApp",
            targets: ["ExampleSmallApp"]
        ),
        .executable(name: "ExampleModularApp", targets: ["ExampleModularApp"]),
        .executable(name: "ExampleSessionApp", targets: ["ExampleSessionApp"]),
        .executable(name: "ExampleStressApp", targets: ["ExampleStressApp"]),

        // Preview-hosting libraries.
        //
        // Xcode 15+ refuses to render SwiftUI previews from an executable
        // target unless `ENABLE_DEBUG_DYLIB=YES` — a setting SwiftPM does not
        // surface. The previewable views therefore live in `*Core` library
        // targets, but for Xcode to generate a scheme that can *select* them
        // as the preview host, those targets must also be exposed as
        // products. Selecting the `ExampleSmallAppCore` (or
        // `ExampleModularAppCore`) scheme in Xcode lets `#Preview { … }` in
        // the library compile and render normally.
        .library(name: "ExampleSmallAppCore", targets: ["ExampleSmallAppCore"]),
        .library(name: "ExampleModularAppCore", targets: ["ExampleModularAppCore"]),
        .library(name: "ExampleStressAppCore", targets: ["ExampleStressAppCore"]),
    ],
    dependencies: [
        // Only swiftlang dependency. Required by the macros plugin.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        // MARK: - Core

        .target(
            name: "Dependence",
            path: "Sources/Dependence",
            swiftSettings: .strict
        ),

        // MARK: - Macros

        .macro(
            name: "DependenceMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ],
            path: "Sources/DependenceMacrosPlugin",
            swiftSettings: .strict
        ),
        .target(
            name: "DependenceMacros",
            dependencies: [
                "Dependence",
                "DependenceMacrosPlugin",
            ],
            path: "Sources/DependenceMacros",
            swiftSettings: .strict
        ),

        // MARK: - Testing support

        .target(
            name: "DependenceTesting",
            dependencies: ["Dependence"],
            path: "Sources/DependenceTesting",
            swiftSettings: .strict
        ),

        // MARK: - Platform adapters

        .target(
            name: "DependenceUIKit",
            dependencies: ["Dependence"],
            path: "Sources/DependenceUIKit",
            swiftSettings: .strict
        ),
        .target(
            name: "DependenceAppKit",
            dependencies: ["Dependence"],
            path: "Sources/DependenceAppKit",
            swiftSettings: .strict
        ),
        .target(
            name: "DependenceAppIntents",
            dependencies: ["Dependence"],
            path: "Sources/DependenceAppIntents",
            swiftSettings: .strict
        ),

        // MARK: - Examples

        // — Small app: a library holds the preview-able UI; the executable
        //   is a thin `@main App` shell. Splitting is required so Xcode can
        //   host SwiftUI previews — executable targets demand
        //   `ENABLE_DEBUG_DYLIB`, which SwiftPM does not expose.

        .target(
            name: "ExampleSmallAppCore",
            dependencies: [
                "Dependence",
                "DependenceMacros",
            ],
            path: "Examples/SmallAppCore",
            swiftSettings: .strict
        ),
        .executableTarget(
            name: "ExampleSmallApp",
            dependencies: [
                "Dependence",
                "ExampleSmallAppCore",
            ],
            path: "Examples/SmallApp",
            exclude: ["Info.plist"],
            swiftSettings: .strict,
            linkerSettings: .embedInfoPlist("Examples/SmallApp/Info.plist")
        ),

        // — Modular example: feature triplets.

        .target(
            name: "AuthInterface",
            dependencies: ["Dependence", "DependenceMacros"],
            path: "Examples/Modular/AuthInterface",
            swiftSettings: .strict
        ),
        .target(
            name: "AuthImpl",
            dependencies: ["AuthInterface"],
            path: "Examples/Modular/AuthImpl",
            swiftSettings: .strict
        ),
        .target(
            name: "AuthTestSupport",
            dependencies: ["AuthInterface"],
            path: "Examples/Modular/AuthTestSupport",
            swiftSettings: .strict
        ),

        .target(
            name: "FeedInterface",
            dependencies: ["Dependence", "DependenceMacros"],
            path: "Examples/Modular/FeedInterface",
            swiftSettings: .strict
        ),
        .target(
            name: "FeedImpl",
            dependencies: ["FeedInterface", "AuthInterface"],
            path: "Examples/Modular/FeedImpl",
            swiftSettings: .strict
        ),
        .target(
            name: "FeedTestSupport",
            dependencies: ["FeedInterface"],
            path: "Examples/Modular/FeedTestSupport",
            swiftSettings: .strict
        ),

        .target(
            name: "ProfileInterface",
            dependencies: ["Dependence", "DependenceMacros"],
            path: "Examples/Modular/ProfileInterface",
            swiftSettings: .strict
        ),
        .target(
            name: "ProfileImpl",
            dependencies: ["ProfileInterface", "AuthInterface"],
            path: "Examples/Modular/ProfileImpl",
            swiftSettings: .strict
        ),
        .target(
            name: "ProfileTestSupport",
            dependencies: ["ProfileInterface"],
            path: "Examples/Modular/ProfileTestSupport",
            swiftSettings: .strict
        ),

        // — Modular app: same library/exec split as the small app, plus the
        //   feature triplets defined above.

        .target(
            name: "ExampleModularAppCore",
            dependencies: [
                "Dependence",
                "DependenceMacros",
                "AuthInterface",
                "FeedInterface",
                "ProfileInterface",
            ],
            path: "Examples/Modular/ExampleModularAppCore",
            swiftSettings: .strict
        ),
        .executableTarget(
            name: "ExampleModularApp",
            dependencies: [
                "Dependence",
                "ExampleModularAppCore",
                "AuthInterface", "AuthImpl",
                "FeedInterface", "FeedImpl",
                "ProfileInterface", "ProfileImpl",
            ],
            path: "Examples/Modular/ExampleModularApp",
            exclude: ["Info.plist"],
            swiftSettings: .strict,
            linkerSettings: .embedInfoPlist("Examples/Modular/ExampleModularApp/Info.plist")
        ),

        .executableTarget(
            name: "ExampleSessionApp",
            dependencies: [
                "Dependence",
                "DependenceMacros",
            ],
            path: "Examples/Session",
            exclude: ["Info.plist"],
            swiftSettings: .strict,
            linkerSettings: .embedInfoPlist("Examples/Session/Info.plist")
        ),

        // — Stress example: a wide registry (8 HTTP clients + 12 services) wired
        //   through `@DependencyEntry`/`@DependencyClient`/`@Dependencies`, plus
        //   a headless benchmark harness in `StressBench`. The same library/exec
        //   split as the other examples: previewable UI lives in `*Core`, the
        //   executable shell forwards `--bench …` to the harness.

        .target(
            name: "ExampleStressAppCore",
            dependencies: [
                "Dependence",
                "DependenceMacros",
            ],
            path: "Examples/Stress/StressAppCore",
            swiftSettings: .strict
        ),
        .executableTarget(
            name: "ExampleStressApp",
            dependencies: [
                "Dependence",
                "ExampleStressAppCore",
            ],
            path: "Examples/Stress/StressApp",
            exclude: ["Info.plist"],
            swiftSettings: .strict,
            linkerSettings: .embedInfoPlist("Examples/Stress/StressApp/Info.plist")
        ),

        // MARK: - Tests

        // NOTE: deliberately does NOT depend on `DependenceMacros`. The test
        // sources never import it, and an `.xctest` bundle that (even
        // transitively) depends on the macro target trips a SwiftBuild-backend
        // toolchain bug: the compiler plugin's objects are linked into the
        // bundle without their SwiftSyntax libraries. Macro behavior is
        // covered by `DependenceMacrosTests` (plugin-level, links the
        // SwiftSyntax test-support products explicitly) and by the
        // compile-only `DependenceMacrosMainActorFixtures` target.
        .testTarget(
            name: "DependenceTests",
            dependencies: [
                "Dependence",
                "DependenceTesting",
            ],
            path: "Tests/DependenceTests",
            swiftSettings: .strict
        ),
        .testTarget(
            name: "DependenceMacrosTests",
            dependencies: [
                "DependenceMacrosPlugin",
                // The *generic* test support (not SwiftSyntaxMacrosTestSupport,
                // whose assertions call into the XCTest bridge and emit
                // one warning per assertion under Swift Testing). Failures
                // are routed to Issue.record through the failure-handler
                // variant — see MacroAssertions.swift.
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/DependenceMacrosTests",
            swiftSettings: .strict
        ),
        // Compile-only regression target that pins the macro ↔
        // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` interaction. This
        // target sets `defaultIsolation(MainActor.self)` so every
        // declaration in it is implicitly `@MainActor` — the same shape as
        // an Xcode 26 app module built with the default-isolation knob
        // flipped. If `@DependencyClient` or `@DependencyEntry` stop
        // emitting `nonisolated` where required, the fixtures in this
        // target stop compiling.
        //
        // Deliberately a plain `.target`, not a `.testTarget`: under the
        // default (SwiftBuild) backend, an `.xctest` bundle that
        // transitively depends on the macro plugin fails to link — the
        // plugin's object files are pulled into the test bundle without
        // the SwiftSyntax libraries they reference (toolchain bug). The
        // fixtures had no meaningful runtime assertions anyway; the build
        // *is* the test, and `swift build` (run in CI) covers it.
        .target(
            name: "DependenceMacrosMainActorFixtures",
            dependencies: [
                "Dependence",
                "DependenceMacros",
            ],
            path: "Tests/DependenceMacrosMainActorFixtures",
            swiftSettings: .strict + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DependenceTestingTests",
            dependencies: [
                "Dependence",
                "DependenceTesting",
            ],
            path: "Tests/DependenceTestingTests",
            swiftSettings: .strict
        ),
        .testTarget(
            name: "DependenceUIKitTests",
            dependencies: [
                "Dependence",
                "DependenceUIKit",
                "DependenceTesting",
            ],
            path: "Tests/DependenceUIKitTests",
            swiftSettings: .strict
        ),
        .testTarget(
            name: "DependenceAppKitTests",
            dependencies: [
                "Dependence",
                "DependenceAppKit",
                "DependenceTesting",
            ],
            path: "Tests/DependenceAppKitTests",
            swiftSettings: .strict
        ),
        .testTarget(
            name: "DependenceAppIntentsTests",
            dependencies: [
                "Dependence",
                "DependenceAppIntents",
                "DependenceTesting",
            ],
            path: "Tests/DependenceAppIntentsTests",
            swiftSettings: .strict
        ),
        // No direct `DependenceMacros` dependency (unused by the test
        // sources) — but `ExampleStressAppCore` depends on it, and the
        // SwiftBuild backend links the macro *plugin*'s objects into the
        // `.xctest` bundle for that transitive edge (toolchain bug; the
        // native backend does not). The SwiftSyntax products below exist
        // solely to satisfy those spurious plugin symbols at link time.
        // Remove them once the backend stops linking compiler-plugin
        // objects into test bundles.
        .testTarget(
            name: "ExampleStressAppCoreTests",
            dependencies: [
                "Dependence",
                "DependenceTesting",
                "ExampleStressAppCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Tests/ExampleStressAppCoreTests",
            swiftSettings: .strict
        ),
    ],
    swiftLanguageModes: [.v6]
)

// MARK: - Common Swift settings

extension Array where Element == SwiftSetting {
    /// Strict concurrency + warnings-as-errors-friendly defaults.
    fileprivate static var strict: [SwiftSetting] {
        [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        ]
    }
}

// MARK: - Common linker settings

extension Array where Element == LinkerSetting {
    /// Embeds an `Info.plist` into the executable's `__TEXT,__info_plist`
    /// section.
    ///
    /// SwiftPM `.executable` products on iOS-family platforms produce a flat
    /// Mach-O binary, not an `.app` bundle. The simulator's BackBoard refuses
    /// to launch a process whose main bundle has no `CFBundleIdentifier`,
    /// failing with:
    ///
    ///     __BKSHIDEvent__BUNDLE_IDENTIFIER_FOR_CURRENT_PROCESS_IS_NIL__
    ///
    /// Embedding the plist into the binary makes
    /// `CFBundleGetMainBundle()` resolve a real info dictionary at runtime,
    /// which satisfies BackBoard and lets the SwiftUI app launch.
    ///
    /// macOS is excluded because Mach-O CLI executables on macOS don't need
    /// (and shouldn't carry) an iOS-flavoured `Info.plist`. The `path` is
    /// resolved relative to the package root by the linker.
    fileprivate static func embedInfoPlist(_ path: String) -> [LinkerSetting] {
        [
            .unsafeFlags(
                [
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", path,
                ],
                .when(platforms: [.iOS, .tvOS, .visionOS, .watchOS])
            )
        ]
    }
}
