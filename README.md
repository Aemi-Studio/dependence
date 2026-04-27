# `dependence`

A type-driven dependency injection framework for Swift 6.3+, built on
Apple/swiftlang technology only. Targets iOS 26 / macOS 26 / tvOS 26 /
watchOS 26 / visionOS 26 + Linux.

The package ships as the **`Dependence`** family of modules: a Foundation-only
core, an opt-in macros library, a Swift Testing support module, and dedicated
UIKit / AppKit adapters.

## Why another DI library?

Most Swift DI libraries either lean on third-party packages or push runtime
graph resolution. `Dependence` instead leverages five layers of the type
system — capability protocols, protocol witnesses, phantom-typed scopes,
generic constructor injection, and `~Copyable` scope tokens — and keeps the
runtime ambient story honest: a `Sendable` `DependencyValues` struct stored
in a `@TaskLocal`, with SwiftUI `@Environment(\.dependencies)` bridging.

There is **no third-party dependency**. The only external package used is
[`swiftlang/swift-syntax`](https://github.com/swiftlang/swift-syntax), and only
by the macros plugin.

## Modules

| Module | Purpose |
|---|---|
| `Dependence` | Core: `DependencyValues`, `@Dependency`, `withDependencies`, `ScopeToken`, SwiftUI bridge. |
| `DependenceMacros` | Optional ergonomic macros: `@DependencyEntry`, `@DependencyClient`. |
| `DependenceTesting` | `TestClock`, `ImmediateClock`, `UnimplementedClock`, `DependenciesTrait` for Swift Testing. |
| `DependenceUIKit` | `UITraitDefinition`-based adapter for the UIKit responder/trait chain. |
| `DependenceAppKit` | `NSResponder`-based adapter for AppKit document and window-controller hierarchies. |

## Quick start

```swift
// 1. Declare a witness — a struct of @Sendable closures.
import Dependence
import DependenceMacros

@DependencyClient
public struct APIClient: Sendable {
    public var fetchGreeting: @Sendable () async throws -> String
}

extension APIClient {
    public static let live = APIClient(fetchGreeting: { "hello, world" })
}

// 2. Register it on DependencyValues.
extension DependencyValues {
    @DependencyEntry public var apiClient: APIClient = .live
}

// 3. Read it from any code, including SwiftUI views.
import SwiftUI

@MainActor @Observable
final class GreetingViewModel {
    @ObservationIgnored @Dependency(\.apiClient) var api
    var greeting = "…"
    func load() async { greeting = (try? await api.fetchGreeting()) ?? "—" }
}

// 4. Override anywhere — globally, per-task, per-SwiftUI-subtree, per-test.
withDependencies {
    $0.apiClient = APIClient(fetchGreeting: { "from a test" })
} operation: {
    // …code reading @Dependency(\.apiClient) sees the override.
}
```

## Examples

The package ships three executable example targets:

- **`ExampleSmallApp`** — single SwiftUI target showing `@Dependency`,
  subtree overrides via `.dependencies { }`, and a `#Preview` override.
- **`ExampleModularApp`** — Interface / Impl / TestSupport split across three
  features (Auth, Feed, Profile) plus a composition root. Demonstrates that
  feature interface modules never need to import each other's live impls.
- **`ExampleSessionApp`** — `~Copyable` `ScopeToken` for a post-login
  session. The compiler enforces single-consumption and prevents leaks.

Build any of them with `swift build --target <name>`.

## Testing

```swift
import Dependence
import DependenceTesting
import Testing

@Suite(.dependencies { $0.apiClient = APIClient(fetchGreeting: { "x" }) })
struct ExampleTests {
    @Test func greets() async throws {
        @Dependency(\.apiClient) var api
        #expect(try await api.fetchGreeting() == "x")
    }
}
```

`TestClock` lets you drive time deterministically:

```swift
@Test func tick() async {
    let clock = TestClock()
    await withTaskGroup(of: Void.self) { group in
        group.addTask { try? await clock.sleep(for: .seconds(1)) }
        await clock.advance(by: .seconds(1))
        for await _ in group {}
    }
}
```

## Status

All five core modules build cleanly with strict concurrency on Swift 6.3.
Full test suite passes. See `docs/artifact_1.md` for the architectural
research that motivated the design.
