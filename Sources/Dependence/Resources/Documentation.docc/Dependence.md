# ``Dependence``

A Swift 6.3 native dependency-injection framework that scales from single-target apps to large modular SPM projects.

## Overview

`Dependence` is built around a `Sendable` ``DependencyValues`` struct stored
in a `@TaskLocal`, with `withDependencies { } operation: { }` for scoped
overrides and a `live` / `preview` / `test` value trichotomy. Service shapes
are typically `Sendable` structs of `@Sendable` closures (the "witness"
pattern), and generational lifetimes use `~Copyable` scope tokens.

## Topics

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
- ``Lazy``

### Generational Scopes
- ``ScopeToken``
- ``ScopeTag``

### Diagnostics
- ``DependencyError``
- ``reportIssue(_:fileID:filePath:line:column:)``
