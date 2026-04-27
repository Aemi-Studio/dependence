# dependence

`dependence` is a Swift 6.3+ dependency-injection package built around typed
dependency keys, `Sendable` witness values, and `@TaskLocal` scoped overrides.
It is designed for SwiftPM-first apps that want explicit composition roots,
parallel-safe tests, preview-safe defaults, and platform-native bridges for
SwiftUI, UIKit, and AppKit.

The core product has no third-party runtime dependency. The optional macro
product depends on `swiftlang/swift-syntax` only at build time.

## Requirements

- Swift tools version: 6.3
- Swift language mode: 6
- Apple platforms declared by the package: iOS 26, macOS 26, tvOS 26,
  watchOS 26, visionOS 26
- Linux: supported by the core and testing targets where the Swift toolchain
  provides the required standard library modules

## Products

| Product | What it contains |
| --- | --- |
| `Dependence` | Core `DependencyValues`, `DependencyKey`, `@Dependency`, `withDependencies`, `prepareDependencies`, `Provider`, `Lazy`, `ScopeToken`, issue reporting, and the conditional SwiftUI bridge. |
| `DependenceMacros` | Optional macros: `@DependencyEntry`, `@DependencyClient`, and `@Dependencies`. Re-exports `Dependence`. |
| `DependenceTesting` | Swift Testing integration, `.dependencies { }` traits, `TestClock`, `ImmediateClock`, and `UnimplementedClock`. |
| `DependenceUIKit` | UIKit trait-chain storage, `UIViewController.dependencies`, `UIView.dependencies`, and observation helpers. |
| `DependenceAppKit` | AppKit responder-chain lookup and `NSDocument`-scoped dependency storage. |

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Aemi-Studio/dependence.git", branch: "main"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "Dependence", package: "dependence"),
            .product(name: "DependenceMacros", package: "dependence"), // optional
        ]
    ),
    .testTarget(
        name: "MyAppTests",
        dependencies: [
            "MyApp",
            .product(name: "DependenceTesting", package: "dependence"),
        ]
    ),
]
```

Import only what each target needs:

```swift
import Dependence
import DependenceMacros    // only in targets that use macros
import DependenceTesting   // tests only
import DependenceUIKit     // UIKit adapters
import DependenceAppKit    // AppKit adapters
```

## Quick Start

Declare service clients as `Sendable` structs of `@Sendable` closures. This
"witness" shape makes live, preview, and test implementations ordinary values.

```swift
import Dependence
import DependenceMacros

@DependencyClient
public struct APIClient: Sendable {
    public var fetchGreeting: @Sendable () async throws -> String
}

extension APIClient {
    public static let live = APIClient(
        fetchGreeting: { "hello, world" }
    )

    public static let preview = APIClient(
        fetchGreeting: { "hello from preview" }
    )
}

extension DependencyValues {
    @DependencyEntry(
        preview: APIClient.preview,
        test: APIClient.unimplemented
    )
    public var apiClient: APIClient = .live
}
```

Read the value with `@Dependency`:

```swift
import Dependence
import DependenceMacros
import Observation

@MainActor
@Observable
@Dependencies(\.apiClient)
final class GreetingViewModel {
    private(set) var greeting = ""

    func load() async throws {
        greeting = try await apiClient.fetchGreeting()
    }
}
```

Override it for a lexical task scope:

```swift
try await withDependencies {
    $0.apiClient = APIClient(fetchGreeting: { "from test" })
} operation: {
    let model = await MainActor.run { GreetingViewModel() }
    try await model.load()
}
```

## Core Model

Every dependency is identified by a key type. A key supplies default values for
runtime, previews, and tests:

```swift
enum APIClientKey: DependencyKey {
    static var liveValue: APIClient { .live }
    static var previewValue: APIClient { .preview }
    static var testValue: APIClient { .unimplemented }
}

extension DependencyValues {
    var apiClient: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
```

`@DependencyEntry` writes that boilerplate for the common case. The manual form
remains useful when the macro convention does not fit.

`DependencyValues` is a `Sendable` value type. Explicit overrides live in the
current `DependencyValues` instance. Default values are resolved lazily and
cached process-wide by dependency key and execution context.

## Default Resolution

For a full `DependencyKey`, defaults resolve as follows:

| Context | Default value |
| --- | --- |
| App/runtime | `liveValue` |
| SwiftUI preview process | `previewValue` |
| Swift Testing | `testValue` |
| XCTest | `testValue` |

For `TestDependencyKey`, which is used by interface-only modules that cannot
see a live implementation, defaults resolve as follows:

| Context | Default value |
| --- | --- |
| App/runtime | `testValue` |
| SwiftUI preview process | `previewValue` |
| Swift Testing | `testValue` |
| XCTest | `testValue` |

Fallbacks are inherited from the protocols:

- `TestDependencyKey.previewValue` defaults to `testValue`.
- `DependencyKey.testValue` defaults to `liveValue`.
- Therefore, a bare `DependencyKey` with only `liveValue` uses `liveValue` in
  runtime, preview, and test contexts.

The preview detector checks `XCODE_RUNNING_FOR_PREVIEWS == "1"` before test
framework probes so Xcode previews get `previewValue` even if XCTest is loaded
by the preview host.

## Override Scopes

`withDependencies` copies the currently bound task-local values, applies your
mutations, and binds that copy for the duration of the operation.

```swift
withDependencies {
    $0.apiClient = .preview
} operation: {
    // Synchronous reads see .preview here.
}

await withDependencies {
    $0.apiClient = .preview
} operation: {
    // Structured child tasks inherit the override.
}
```

Nested overrides compose. Inner mutations shadow outer mutations for the same
key while inheriting all other keys.

Structured concurrency inherits overrides automatically:

- `async let` inherits.
- `withTaskGroup.addTask` inherits.
- `Task.detached`, GCD, Combine callbacks, and NotificationCenter callbacks do
  not inherit.

Use `captureDependencies()` immediately before crossing an escaping boundary:

```swift
let continuation = captureDependencies()

DispatchQueue.global().async {
    continuation.yield {
        // Reads are rebound to the captured TaskLocal dependency values.
    }
}
```

`captureDependencies()` captures the active task-local values. It does not
capture a SwiftUI `@Environment` snapshot by itself.

## SwiftUI Behavior

`Dependence` conditionally bridges into SwiftUI when SwiftUI is available.

At the app composition root, use the scene modifier:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .dependencies {
                $0.apiClient = .live
            }
    }
}
```

The first scene evaluation seeds the process-wide default cache. Later scene
reevaluations are silent no-ops for the global install, so treat this as a
composition-root API, not a dynamic reconfiguration mechanism.

For previews, feature flags, and local branches, use the view modifier:

```swift
RootView()
    .dependencies {
        $0.apiClient = .preview
    }
```

The view modifier writes the override into SwiftUI `EnvironmentValues` and also
publishes a subtree entry so non-View hosts, such as `@Observable` view models,
can resolve the same override.

Resolution precedence depends on where the read happens:

| Read site | Precedence |
| --- | --- |
| `@Dependency` installed on a SwiftUI `View` or `ViewModifier` | SwiftUI environment override, then task-local override, then subtree fallback, then defaults. |
| `@Dependency` on a non-View host | Task-local override, then latest SwiftUI subtree fallback, then defaults. |
| `DependencyValues.current` | Task-local override, then latest SwiftUI subtree fallback, then defaults. |
| Direct subscript on a specific `DependencyValues` value | That value's overrides, then cached/context defaults. |

Empty override containers are ignored in the environment/subtree fallback path.

For Xcode previews, `DependencePreview` wraps the view modifier in Apple's
`PreviewModifier` shape:

```swift
#Preview(traits: .modifier(DependencePreview { $0.apiClient = .preview })) {
    RootView()
}
```

If a key has `@DependencyEntry(preview: ...)`, previews can often rely on the
automatic `previewValue` without any modifier.

## Composition Root

For non-SwiftUI apps, or for apps that prefer explicit startup wiring, call
`prepareDependencies` once at the very beginning of the process:

```swift
@main
enum AppMain {
    static func main() async throws {
        prepareDependencies {
            $0.apiClient = .live
        }

        try await run()
    }
}
```

The first call installs the supplied values into the process-wide cache for all
execution contexts. A second call reports an issue and is ignored. Configure all
live dependencies in one composition root.

## Modular Interface/Implementation Split

`TestDependencyKey` lets an interface module declare a dependency slot without
importing the live implementation.

```swift
// AuthInterface
public enum AuthClientKey: TestDependencyKey {
    public static var testValue: AuthClient { .unimplemented }
    public static var previewValue: AuthClient { .preview }
}

extension DependencyValues {
    @DependencyEntry public var authClient: AuthClient
}
```

The no-initializer macro form routes through a key named from the value type:
`AuthClient` -> `AuthClientKey`. The implementation module then adds the live
conformance:

```swift
// AuthImpl
extension AuthClientKey: DependencyKey {
    public static var liveValue: AuthClient { .live }
}
```

Only the app target imports `AuthImpl` and wires `.live`. Feature modules can
depend only on `AuthInterface`.

## Macros

`DependenceMacros` is optional. All generated code is ordinary Swift that can be
written manually.

### `@DependencyEntry`

With an initializer:

```swift
@DependencyEntry(preview: APIClient.preview, test: APIClient.unimplemented)
public var apiClient: APIClient = .live
```

The macro generates:

- A fileprivate `__Key_apiClient` type conforming to `DependencyKey`.
- `liveValue` from the initializer expression.
- Optional `previewValue` and `testValue` witnesses from labeled arguments.
- A get/set accessor routed through `self[__Key_apiClient.self]`.

Without an initializer:

```swift
@DependencyEntry public var authClient: AuthClient
```

The macro generates accessors routed through `self[test: AuthClientKey.self]`.
The external key must conform to `TestDependencyKey`, and a live module may
later conform it to `DependencyKey`.

### `@DependencyClient`

Use on a struct of closure properties:

```swift
@DependencyClient
public struct SearchClient: Sendable {
    public var search: @Sendable (String) async throws -> [String]
    public var cancel: @Sendable () -> Void
}
```

The macro generates a memberwise initializer. Closure parameters default to
unimplemented closures:

- Throwing closures report an issue and throw `DependencyError.unimplemented`.
- `Void` closures report an issue and return.
- Non-throwing, non-`Void` closures report an issue and then trap because there
  is no value to return. The macro emits a warning for this shape; prefer
  `throws` if the unimplemented path should be recoverable in tests.
- Non-closure stored properties become required initializer parameters.
- `static var unimplemented` is generated only when every stored property can
  be defaulted.

### `@Dependencies`

Use on `@Observable` view models and similar classes:

```swift
@Dependencies(\.authClient, \.feedClient)
final class HomeViewModel {}
```

The macro generates private stored properties:

```swift
@ObservationIgnored
@Dependence.Dependency(\.authClient) private var authClient
```

Each key path must contain exactly one property component, such as
`\.authClient`. Duplicate key paths are skipped.

## Testing

`DependenceTesting` integrates with Swift Testing:

```swift
import Dependence
import DependenceTesting
import Testing

@Suite(.dependencies { $0.apiClient = .preview })
struct GreetingTests {
    @Test(.dependencies { $0.apiClient = APIClient(fetchGreeting: { "test" }) })
    func greets() async throws {
        @Dependency(\.apiClient) var api
        #expect(try await api.fetchGreeting() == "test")
    }
}
```

Suite traits are recursive. Test-level traits layer on top of suite-level
traits, and the inner mutation wins on conflicts.

`DependenceTesting` also installs Swift Testing issue routing. Once a testing
API from this product is touched, `reportIssue` calls made inside a running
`@Test` are recorded with `Issue.record`.

### Test Clocks

`TestClock` is deterministic. Sleeps suspend until the test advances the clock.

```swift
let clock = TestClock()

async let value: Void = clock.sleep(for: .seconds(1))
await clock.advance(by: .seconds(1))
try await value
```

`advance(by:)` and `advance(to:)` resume sleepers whose deadlines have passed,
in deadline order. `run()` drains all pending sleepers. Cancellation resumes
sleepers with `CancellationError`.

`ImmediateClock` never actually sleeps. It advances its local `now` to the
requested deadline, yields once, and honors cancellation.

`UnimplementedClock` reports an issue whenever `now`, `minimumResolution`, or
`sleep` is used. It is intended as a test default for clock dependencies.

## UIKit

`DependenceUIKit` stores `DependencyValues` in the UIKit trait chain:

```swift
containerViewController.dependencies {
    $0.apiClient = .preview
}

let values = view.traitCollection.dependencies
```

`UIViewController.dependencies` and `UIView.dependencies` start from currently
inherited trait values, apply your mutation, and write the result to
`traitOverrides.dependencies`.

For explicit Observation tracking, use:

```swift
withObservedDependencies({ values in
    values.apiClient
}, onChange: {
    view.setNeedsLayout()
})
```

The helper uses `withObservationTracking` and invokes `onChange` once on the
main actor. Re-arm it after a change if you need continuous observation.

## AppKit

`DependenceAppKit` uses the responder chain:

```swift
@MainActor
final class WindowController: NSWindowController, DependencyHosting {
    var dependencies = DependencyValues()
}

let values = someResponder.inheritedDependencies
```

`inheritedDependencies` walks `nextResponder` until it finds a
`DependencyHosting` responder, then returns that host's values. If no host is
found, it returns an empty container.

`NSDocument` conforms to `DependencyHosting` through associated-object storage,
so document-based apps can scope dependencies per document.

## Providers, Lazy Values, and Scope Tokens

Use `Provider<Value>` for "make a fresh value every time":

```swift
struct LoginClient: Sendable {
    var makeAttempt: Provider<LoginAttempt>
}
```

Use `AsyncProvider<Value>` for async factories.

Use `Lazy<Value>` for "initialize on first use and cache":

```swift
let expensive = Lazy { ExpensiveClient() }
let client = expensive()
```

`Lazy` computes outside its lock so dependencies can be read during
construction without deadlocking. Under contention, more than one caller may
run the producer closure, but only the first installed value is stored and
returned thereafter. Keep the producer side-effect-safe.

Use `ScopeToken<Tag, Value>` for single-use generational scopes such as a
post-login session:

```swift
enum SessionScope: ScopeTag {}

let session = ScopeToken<SessionScope, User>(
    value: user,
    teardown: { print("session ended") }
)

await session.enter { borrowed in
    let user = borrowed.snapshot()
    await withDependencies {
        $0.currentUser = user
    } operation: {
        await runAuthenticatedShell()
    }
}
```

`ScopeToken` is `~Copyable`. The compiler rejects copies and use after consume.
`enter` runs teardown whether the operation returns or throws. `close()` consumes
the token and runs teardown without running an operation.

## Issue Reporting

`reportIssue` is used for unimplemented sentinels and recoverable
misconfigurations.

Routing is context-aware:

| Context | Sink |
| --- | --- |
| Swift Testing with `DependenceTesting` bootstrapped | `Issue.record` |
| Swift Testing without a registered handler | runtime warning |
| XCTest | `[XCTest]`-prefixed runtime warning |
| SwiftUI preview or runtime | runtime warning |

On Apple platforms, runtime warnings use `os.Logger`. In debug builds they are
logged as faults so Xcode surfaces them prominently. On non-Apple platforms,
warnings are written to `stderr`.

## Examples

The package includes executable examples:

| Target | Demonstrates |
| --- | --- |
| `ExampleSmallApp` | A single SwiftUI app with `@Dependency`, `@Dependencies`, preview defaults, and subtree overrides. |
| `ExampleModularApp` | Interface/implementation/test-support module split for Auth, Feed, and Profile features. |
| `ExampleSessionApp` | `ScopeToken` for a post-login session lifetime. |
| `ExampleStressApp` | A 20-key dependency registry, macro-heavy registration, nested overrides, graph walking, and benchmark hooks. |

Build an example with:

```bash
swift build --product ExampleSmallApp
```

Run stress benchmarks with:

```bash
Tools/stress-profile.sh
```

## Guarantees and Boundaries

`dependence` guarantees typed key-path access, `Sendable` dependency storage,
parallel-safe task-local overrides, deterministic test traits, and native
SwiftUI/UIKit/AppKit integration.

It does not perform whole-program graph validation. A key path proves the slot
exists; it does not prove every app composition root remembered to install a
live value. Use interface/implementation module boundaries, unimplemented test
defaults, and focused tests to keep that honest.

Detached tasks and callback APIs do not inherit task-local values. Capture and
rebind explicitly with `captureDependencies()`.

Non-`Sendable` services should be wrapped behind actors, isolated to the main
actor, or represented by `Sendable` witnesses. Avoid storing arbitrary
non-thread-safe reference types directly in `DependencyValues`.

## Project Documentation

DocC documentation starts at
`Sources/Dependence/Resources/Documentation.docc/Dependence.md`, with the
behavior reference in
`Sources/Dependence/Resources/Documentation.docc/Behavior.md`.

The files in `docs/artifact_*.md` are historical design research. They are
useful background, but the README and DocC pages are the canonical description
of the implemented package behavior.
