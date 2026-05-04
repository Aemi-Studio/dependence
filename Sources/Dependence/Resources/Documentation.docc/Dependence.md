# ``Dependence``

A Swift 6.3 native dependency-injection package for typed dependency keys,
task-local overrides, preview-safe defaults, and platform-native SwiftUI,
UIKit, and AppKit bridges.

## Overview

`Dependence` stores dependency values in a `Sendable` ``DependencyValues``
struct. Scoped overrides are bound through `@TaskLocal` by
``withDependencies(_:operation:)``, default values are supplied by typed
``DependencyKey`` and ``TestDependencyKey`` conformances, and SwiftUI subtree
overrides flow through `EnvironmentValues.dependencies`.

The package is split into focused products:

- `Dependence`: core keys, values, property wrapper, scoped overrides, issue
  reporting, SwiftUI bridge, providers, lazy values, and scope tokens.
- `DependenceMacros`: optional `@DependencyEntry`, `@DependencyClient`, and
  `@Dependencies` macros.
- `DependenceTesting`: Swift Testing traits and deterministic clocks.
- `DependenceUIKit`: UIKit trait-chain integration.
- `DependenceAppKit`: AppKit responder-chain and document integration.

Dependencies are typically modeled as `Sendable` structs of `@Sendable`
closures. This witness style makes live, preview, and test implementations
ordinary values that compose with overrides.

For the precise resolution order, context defaults, platform bridge behavior,
macro expansion contracts, and known boundaries, read <doc:Behavior>.

## Topics

### Articles
- <doc:Behavior>
- <doc:Lifetime>

### Essentials
- ``DependencyValues``
- ``DependencyKey``
- ``TestDependencyKey``
- ``Dependency``

### Scoping
- ``withDependencies(_:operation:)``
- ``prepareDependencies(_:)``
- ``captureDependencies()``
- ``DependencyContinuation``

### Service Shapes
- ``Provider``
- ``AsyncProvider``
- ``Lazy``

### Generational Scopes
- ``ScopeToken``
- ``ScopeTag``

### Diagnostics
- ``DependencyError``
- ``reportIssue(_:fileID:filePath:line:column:)``
