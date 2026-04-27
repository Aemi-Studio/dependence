# Package Behavior

This article is the canonical behavior reference for `Dependence`.

## Dependency Defaults

A full ``DependencyKey`` supplies a production value and may override preview
and test values:

```swift
enum APIClientKey: DependencyKey {
    static var liveValue: APIClient { .live }
    static var previewValue: APIClient { .preview }
    static var testValue: APIClient { .unimplemented }
}
```

Resolution for `DependencyKey`:

| Context | Value |
| --- | --- |
| Runtime | `liveValue` |
| SwiftUI preview | `previewValue` |
| Swift Testing | `testValue` |
| XCTest | `testValue` |

`DependencyKey.testValue` defaults to `liveValue`.
`TestDependencyKey.previewValue` defaults to `testValue`. Therefore a key with
only `liveValue` uses that value in all contexts.

``TestDependencyKey`` is for interface-only modules that cannot import a live
implementation:

```swift
public enum AuthClientKey: TestDependencyKey {
    public static var testValue: AuthClient { .unimplemented }
    public static var previewValue: AuthClient { .preview }
}
```

Resolution for `TestDependencyKey`:

| Context | Value |
| --- | --- |
| Runtime | `testValue` |
| SwiftUI preview | `previewValue` |
| Swift Testing | `testValue` |
| XCTest | `testValue` |

The preview detector checks `XCODE_RUNNING_FOR_PREVIEWS == "1"` before test
framework probes. This keeps previews on `previewValue` even when the preview
host has XCTest loaded.

## Caching

Default values are resolved lazily and cached process-wide by dependency key
and execution context. Explicit overrides stored on a ``DependencyValues`` value
take precedence over the cache.

The default is computed outside the cache lock, then installed with a
double-check. This prevents deadlocks when one default reads another dependency.
If two tasks race to compute the same default, the first installed value wins.

``prepareDependencies(_:)`` writes its explicit overrides directly into the
process-wide cache for every execution context. The first call wins; later
calls report an issue and are ignored.

## Override Propagation

``withDependencies(_:operation:)`` copies the currently bound task-local
container, applies mutations, and binds the copy while `operation` runs.

Nested overrides compose. Inner mutations shadow outer mutations for the same
key and inherit all unrelated keys.

Structured child tasks inherit the binding automatically:

- `async let`
- `withTaskGroup.addTask`

Unstructured boundaries do not inherit:

- `Task.detached`
- GCD
- Combine callbacks
- NotificationCenter callbacks
- Other escaping closures invoked outside the task tree

Use ``captureDependencies()`` before crossing such a boundary, then call
`DependencyContinuation.yield` on the other side.

`captureDependencies()` captures the active task-local values. It does not
capture SwiftUI environment snapshots by itself.

## Read Precedence

Read precedence depends on where the dependency is read.

For `@Dependency` installed on a SwiftUI `View` or `ViewModifier` after SwiftUI
has called `DynamicProperty.update()`:

1. Non-empty SwiftUI `EnvironmentValues.dependencies`
2. Non-empty task-local override
3. Latest non-empty SwiftUI subtree fallback
4. Context default

For `@Dependency` on a non-View host, such as an `@Observable` view model:

1. Non-empty task-local override
2. Latest non-empty SwiftUI subtree fallback
3. Context default

For ``DependencyValues/current``:

1. Non-empty task-local override
2. Latest non-empty SwiftUI subtree fallback
3. Context default

For a direct subscript on a specific ``DependencyValues`` instance:

1. Overrides stored in that instance
2. Context default

Empty override containers are ignored in the environment and subtree fallback
paths.

## SwiftUI

`View.dependencies(_:)` is a subtree override. It writes the mutated values into
SwiftUI environment and publishes a subtree entry so non-View hosts can resolve
the same values.

`Scene.dependencies(_:)` is a composition-root install. It prepares the global
cache once and also sets the scene environment. Repeated scene body evaluation
does not reinstall process-wide values.

``DependencePreview`` adapts the view modifier to SwiftUI's `PreviewModifier`
API.

## Macros

The macro product is optional. Generated code is ordinary Swift.

`@DependencyEntry` with an initializer generates a fileprivate
`DependencyKey`, routes get/set through that key, and stamps any `preview:` or
`test:` arguments into the key conformance.

`@DependencyEntry` without an initializer routes through an external key named
from the value type, such as `AuthClientKey`. That external key must conform to
``TestDependencyKey`` and may later be extended to ``DependencyKey`` by a live
implementation module.

`@DependencyClient` generates a memberwise initializer for a struct. Closure
properties default to unimplemented closures. Throwing closures throw
`DependencyError.unimplemented` after reporting. `Void` closures only
report. Non-throwing, non-`Void` closures report and then trap because no value
can be returned.

`@Dependencies` generates private `@ObservationIgnored @Dependency` stored
properties for one-component key paths such as `\.apiClient`. Duplicate key
paths are skipped.

## Testing

`DependenceTesting` provides a recursive Swift Testing trait:

```swift
@Suite(.dependencies { $0.apiClient = .preview })
struct APITests {
    @Test(.dependencies { $0.apiClient = .mock })
    func success() {}
}
```

Suite-level traits apply to every test in the suite. Test-level traits layer on
top and shadow conflicts.

`DependenceTesting` also bootstraps `reportIssue` routing to Swift Testing's
`Issue.record` when a `reportIssue` call happens inside a running `@Test`.

``TestClock`` suspends sleepers until the test advances time and resumes
eligible sleepers in deadline order. ``ImmediateClock`` advances its local time
without sleeping and honors cancellation. ``UnimplementedClock`` reports an
issue on every interaction.

## Platform Adapters

`DependenceUIKit` stores values in UIKit traits. `UIViewController` and `UIView`
convenience methods mutate inherited trait values and write the result to
`traitOverrides.dependencies`. `withObservedDependencies` uses Observation's
fire-once `withObservationTracking`; callers should re-arm it after changes.

`DependenceAppKit` resolves values by walking `NSResponder.nextResponder` until
it finds a `DependencyHosting` responder. `NSDocument` stores per-document
values through Objective-C associated objects and conforms to
`DependencyHosting`.

## Providers, Lazy Values, and Scope Tokens

``Provider`` and ``AsyncProvider`` call their factory every time.

``Lazy`` caches the first value installed under its lock. Its producer runs
outside the lock to avoid deadlocks, so multiple racing callers may run the
producer, but only one result is stored.

``ScopeToken`` is non-copyable. `enter` consumes the token, borrows it during
the operation, and runs teardown whether the operation returns or throws.
`close()` consumes the token and runs teardown without an operation.

## Boundaries

`Dependence` does not perform whole-program graph validation. A key path proves
that a dependency slot exists; it does not prove that every composition root
installed the intended live value.

Every value stored in ``DependencyValues`` must be `Sendable`. Wrap
non-`Sendable` platform objects behind actors, main-actor-isolated services, or
`Sendable` witnesses.
