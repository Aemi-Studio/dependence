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
        .library(name: "Dependence", targets: ["Dependence"]),

        // Optional ergonomic macros. Importing this product pulls in SwiftSyntax.
        .library(name: "DependenceMacros", targets: ["DependenceMacros"]),

        // Swift Testing trait + TestClock/ImmediateClock/UnimplementedClock.
        .library(name: "DependenceTesting", targets: ["DependenceTesting"]),

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
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
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

        .testTarget(
            name: "DependenceTests",
            dependencies: [
                "Dependence",
                "DependenceMacros",
                "DependenceTesting",
            ],
            path: "Tests/DependenceTests",
            swiftSettings: .strict
        ),
        .testTarget(
            name: "DependenceMacrosTests",
            dependencies: [
                "DependenceMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/DependenceMacrosTests",
            swiftSettings: .strict
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
        .testTarget(
            name: "ExampleStressAppCoreTests",
            dependencies: [
                "Dependence",
                "DependenceMacros",
                "DependenceTesting",
                "ExampleStressAppCore",
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
