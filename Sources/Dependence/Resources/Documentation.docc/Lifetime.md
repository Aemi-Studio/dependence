# Dependency Lifetime and Hotload Matrix

How long a dependency value lives, when it can be replaced, and which read
sites observe the replacement.

## Overview

`Dependence` exposes several APIs that look related but answer different
questions about *time*: when does a value enter the system, when is it
sampled, when does it leave, and what happens if you try to swap it.
Confusing two of these is the most common source of bugs in dependency
systems. This article fixes the contract.

The vocabulary used here matches `withDependencies`, `prepareDependencies`,
``Provider``, ``Lazy``, ``ScopeToken``, ``View/dependencies(_:)``, and
``Scene/dependencies(_:)``. None of it is metaphorical — every claim
corresponds to a directly testable behavior.

## Lifetime Classes

A dependency is one of:

| Class | Bound by | Released by |
| --- | --- | --- |
| **Process-lifetime** | ``prepareDependencies(_:)`` or first ``Scene/dependencies(_:)`` install | process exit |
| **Task-local** | ``withDependencies(_:operation:)`` | the operation closure returning |
| **Subtree** | ``View/dependencies(_:)`` | SwiftUI removing the subtree from the view tree |
| **Captured** | ``captureDependencies()`` snapshot | the ``DependencyContinuation`` going out of scope |
| **Scope-bound** | ``ScopeToken`` | `enter`/`close` running teardown |
| **Per-call** | ``Provider`` / ``AsyncProvider`` factory | each call returns a fresh value |
| **One-shot** | ``Lazy`` | process exit (first installed value wins) |

Each class is a separate axis. Mixing them is fine; assuming one class
behaves like another is not.

## Hotload Matrix

"Hotload" means replacing a dependency value while the app or preview is
still running and having future reads observe the replacement. The package
does not implement a single hotload behavior — it implements several, with
different semantics depending on the read site.

| Read site | Hotloads on | Notes |
| --- | --- | --- |
| `@Dependency` on a `View` / `ViewModifier` | SwiftUI environment update + `DynamicProperty.update()` | The standard SwiftUI invalidation tree applies. |
| `@Dependency` on a non-`View` host (e.g. `@Observable` view model) | every read | Reads ``DependencyValues/current`` dynamically. See *Identity warning* below. |
| ``DependencyValues/current`` | every read | Same precedence as the wrapper above. |
| Stored service value (`let api = ...`) | never | Capture-at-construction. Reassign to update. |
| ``Provider`` factory body that reads `DependencyValues.current` | every call | Closure resolves at invocation time. |
| ``Provider`` factory body that captured a value at construction | never | Closure stored the old value in its capture list. |
| ``Lazy`` | never after first read | First installed result wins. Producer races install one value. |
| ``prepareDependencies(_:)`` install | never after first call | Repeat calls report an issue and are ignored. |
| ``Scene/dependencies(_:)`` process-cache install | never after first body evaluation | The scene environment value updates; the process cache does not. |
| Direct subscript on a captured ``DependencyValues`` instance | never | The instance is a `Sendable` value type; copies don't share state. |

If the read site is not in this table, it does not hotload.

## Resolution Precedence

Read precedence is fixed and does not depend on hotload state.

For `@Dependency` installed on a SwiftUI `View` / `ViewModifier` after
SwiftUI has called `DynamicProperty.update()`:

1. Non-empty SwiftUI `EnvironmentValues.dependencies` snapshot
2. Non-empty task-local override
3. Latest non-empty SwiftUI subtree fallback
4. Context default

For `@Dependency` on a non-`View` host:

1. Non-empty task-local override
2. Latest non-empty SwiftUI subtree fallback
3. Context default

For ``DependencyValues/current``: same as the non-`View` host case.

Empty containers are ignored — they do not pin "this layer is in effect."

## Identity Warning: Non-View Hosts and the Subtree Fallback

The SwiftUI subtree fallback used by non-`View` hosts is a process-wide
last-writer-wins stack. It is *not* identity-safe: a non-`View` host does
not know which SwiftUI subtree owns it.

If two sibling subtrees publish different values, a non-`View` host reading
``DependencyValues/current`` after both have published may observe the
later sibling rather than its own. Long-lived `@State` view models created
under a subtree may also observe a different sibling later.

Two patterns avoid this:

**Pattern A — snapshot at construction** (recommended for long-lived hosts):

```swift
@Environment(\.dependencies) private var ambient
@State private var model: GreetingViewModel?

var body: some View {
    Group {
        if let model { Greeting(model: model) }
    }
    .task {
        let snapshot = ambient
        model = withDependencies({ $0 = snapshot }) {
            GreetingViewModel()
        }
    }
}
```

The model is constructed inside a `withDependencies` block bound to the
captured snapshot, so its `@Dependency` reads resolve through the
task-local layer that wins over the subtree fallback.

**Pattern B — explicit injection** (recommended for testable view models):

```swift
final class GreetingViewModel {
    let api: APIClient
    init(api: APIClient) { self.api = api }
}
```

No ambient read; the dependency is part of the API.

Use the subtree fallback when the host is short-lived and its parent
subtree has clear identity (preview branches, single-screen flows). Avoid
it when sibling subtrees can be active simultaneously.

## Composition-Root vs Subtree

| | ``prepareDependencies(_:)`` | ``Scene/dependencies(_:)`` | ``View/dependencies(_:)`` |
| --- | --- | --- | --- |
| **Scope** | process | process (first body eval) + scene env | subtree |
| **Repeat-call behavior** | reports issue | silent no-op | replaces |
| **Hotload** | no | no (process cache) | yes (subtree env + fallback) |
| **Use for** | startup live wiring | startup live wiring (SwiftUI form) | previews, A/B, tests, subtree overrides |

Direct `view.environment(\.dependencies, …)` is not a supported override
path: it updates SwiftUI view reads but does not publish a subtree
fallback entry, so non-`View` hosts will not observe it. Use
``View/dependencies(_:)`` instead.

## Per-Call and One-Shot

``Provider`` runs its factory on every call. The factory body decides
whether reads see fresh dependencies:

```swift
// Dynamic — sees the latest dependency on each call.
Provider { DependencyValues.current[APIClientKey.self].newAttempt() }

// Captured — frozen at construction.
let api = DependencyValues.current[APIClientKey.self]
let provider = Provider { api.newAttempt() }
```

``Lazy`` runs its producer at most once that *installs*. Under contention
multiple producers may run, but only the first value installed is stored.
The producer runs outside the lock to allow it to read another
``Lazy``/`@Dependency` without deadlock.

A `Lazy` value is *not* hotloadable. Replacing the underlying dependency
after the first read does not affect the cached value. If you need hotload
behavior, use ``Provider`` instead.

## Resource Lifecycle

`Dependence` scopes *lookup*, not *resources*.

- ``View/dependencies(_:)`` removes a subtree-stack entry on disappear.
  It does **not** cancel work, close files, or invalidate continuations.
- ``withDependencies(_:operation:)`` rebinds a task-local. It does **not**
  shut down the previous values.
- ``prepareDependencies(_:)`` writes into a process-wide cache that
  outlives every other scope.

For deterministic teardown — sessions, documents, requests, login flows —
use ``ScopeToken``:

```swift
await session.enter { borrowed in
    await withDependencies({
        $0.currentUser = borrowed.snapshot()
    }) {
        await runAuthenticatedShell()
    }
}
```

`enter` borrows the token for the operation and runs teardown on both
return and throw paths.

## Quick Reference

- Use ``prepareDependencies(_:)`` (or ``Scene/dependencies(_:)``) once at
  startup, for stable live services.
- Use ``View/dependencies(_:)`` for previews, tests, and subtree overrides.
- Use ``withDependencies(_:operation:)`` for lexical/task scopes.
- Use ``captureDependencies()`` immediately before crossing a non-task
  boundary (GCD, Combine, NotificationCenter, `Task.detached`, delegates).
- Use ``Provider`` for fresh-per-call construction.
- Use ``Lazy`` only when one-shot caching is desired and hotload is
  explicitly not required.
- Use ``ScopeToken`` for generational lifetimes that need teardown — and
  remember that ``View/dependencies(_:)`` alone does not tear resources
  down.
- Treat process-wide default values as process-lifetime unless an
  explicitly scoped API says otherwise.
