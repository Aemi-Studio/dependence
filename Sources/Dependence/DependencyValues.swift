//
//  DependencyValues.swift
//  Dependence
//
//  The container struct. Resolution flows through a TaskLocal-backed
//  `DependencyValues` value; per-instance overrides win, then a process-wide
//  cache, then the key's `liveValue`/`previewValue`/`testValue` based on the
//  detected context.
//

import Foundation

/// The dependency container. A `Sendable` value type that you mutate via
/// ``withDependencies(_:operation:)-(_,_)`` and read through
/// ``Dependency`` property wrappers or `@Environment(\.dependencies)`.
///
/// `DependencyValues` is intentionally a plain struct: copying is cheap, and
/// scoped overrides happen by binding a copy on a `@TaskLocal`. Long-lived
/// shared state lives behind `Sendable` actor or class types stored *inside*
/// the values, never on `DependencyValues` itself.
public struct DependencyValues: Sendable {
    /// Per-instance overrides set via ``withDependencies(_:operation:)-(_,_)``.
    /// Keyed by `ObjectIdentifier(K.self)` of the dependency key.
    @usableFromInline
    var overrides: [ObjectIdentifier: any Sendable] = [:]

    /// Composite cache key. Two distinct execution contexts (test/preview/
    /// runtime) resolve a key to potentially different defaults; sharing the
    /// same cache entry across them would freeze whichever ran first.
    @usableFromInline
    struct CacheKey: Hashable, Sendable {
        let id: ObjectIdentifier
        let context: IssueContext
    }

    /// Process-wide cache of resolved values. Shared across all
    /// `DependencyValues` instances. Only used when no override is set.
    @usableFromInline
    static let cache: Locked<[CacheKey: any Sendable]> = .init([:])

    /// One entry on the SwiftUI subtree-override stack.
    @usableFromInline
    struct SubtreeEntry: Sendable {
        @usableFromInline
        let id: UUID

        @usableFromInline
        var values: DependencyValues

        @usableFromInline
        init(id: UUID, values: DependencyValues) {
            self.id = id
            self.values = values
        }
    }

    /// Stack of active SwiftUI subtree overrides published by the
    /// ``SwiftUICore/View/dependencies(_:)`` modifier.
    ///
    /// Each `DependenciesModifier` instance owns a `SubtreeRegistration`
    /// `@StateObject`; on every `body(content:)` evaluation the modifier
    /// upserts its `(id, values)` entry on this stack, and on disappearance
    /// the registration's `deinit` removes it. The stack supports nested and
    /// sibling subtrees correctly: the most-recently published entry wins.
    ///
    /// **Resolution precedence**: this stack sits *below* the `@TaskLocal`-
    /// bound ``_current`` whenever `_current` carries explicit overrides. A
    /// ``withDependencies(_:operation:)-(_,_)`` block layered inside a
    /// `.dependencies { … }` SwiftUI subtree therefore wins entirely. The
    /// stack only matters for non-View hosts (e.g. `@Observable` view
    /// models) that have no `@Environment` pipeline of their own.
    @usableFromInline
    static let _subtreeStack: Locked<[SubtreeEntry]> = .init([])

    /// Convenience read of the top of the subtree stack.
    @usableFromInline
    static var _subtreeOverride: DependencyValues? {
        _subtreeStack.withLock { $0.last?.values }
    }

    /// The currently bound `DependencyValues`. Reading `_current` returns
    /// either the value bound by the nearest enclosing
    /// ``withDependencies(_:operation:)-(_,_)`` block or a fresh empty
    /// container that resolves against `liveValue`/`previewValue`/`testValue`
    /// based on context.
    @TaskLocal
    @usableFromInline
    static var _current: DependencyValues = .init()

    /// Public accessor for the active container.
    ///
    /// Mirrors the resolution chain that ``Dependency`` uses for non-View
    /// hosts:
    ///
    /// 1. The `@TaskLocal`-bound ``_current`` if it carries explicit
    ///    overrides — i.e. a ``withDependencies(_:operation:)-(_,_)`` block
    ///    is in scope.
    /// 2. The top of the SwiftUI subtree stack if any subtree is active —
    ///    so `@Observable` view-model reads from inside a
    ///    `.dependencies { … }` subtree see the override.
    /// 3. The empty `_current`, which falls through to each key's
    ///    `liveValue`/`previewValue`/`testValue` based on context.
    ///
    /// `withDependencies` always wins. The subtree stack is a lower-priority
    /// fallback for non-View hosts that have no `@Environment` pipeline.
    public static var current: DependencyValues {
        if !_current.overrides.isEmpty {
            return _current
        }
        if let subtree = _subtreeOverride, !subtree.overrides.isEmpty {
            return subtree
        }
        return _current
    }

    /// Construct an empty values bag. Equivalent to "no overrides set" — every
    /// resolution falls through to its key's default values.
    public init() {}

    /// Subscript by `DependencyKey` type. The primary lookup primitive used
    /// by the ``Dependency`` property wrapper and by direct callers that need
    /// untyped access (e.g. macros).
    public subscript<K: DependencyKey>(key: K.Type) -> K.Value {
        get {
            // 1. Per-instance override.
            if let override = overrides[ObjectIdentifier(K.self)] as? K.Value {
                return override
            }
            // 2. Cache lookup, then context-aware default.
            return DependencyValues.resolve(K.self)
        }
        set {
            overrides[ObjectIdentifier(K.self)] = newValue
        }
    }

    /// Subscript by `TestDependencyKey` type. Used for keys whose live
    /// implementation lives in a separate module — interface-only consumers
    /// see only the test/preview values.
    public subscript<K: TestDependencyKey>(test key: K.Type) -> K.Value {
        get {
            if let override = overrides[ObjectIdentifier(K.self)] as? K.Value {
                return override
            }
            return DependencyValues.resolveTest(K.self)
        }
        set {
            overrides[ObjectIdentifier(K.self)] = newValue
        }
    }

    // MARK: - Resolution

    @usableFromInline
    static func resolve<K: DependencyKey>(_ keyType: K.Type) -> K.Value {
        let context = IssueContext.current
        let cacheKey = CacheKey(id: ObjectIdentifier(K.self), context: context)
        // Phase 1: locked read. Skip the default computation entirely on hit.
        if let cached = cache.withLock({ $0[cacheKey] as? K.Value }) {
            return cached
        }
        // Phase 2: compute the default *outside* the lock so a default that
        // reads another `@Dependency` (and re-enters the cache lock) cannot
        // deadlock.
        let computed: K.Value
        switch context {
        case .runtime:
            computed = K.liveValue
        case .preview:
            computed = K.previewValue
        case .swiftTesting, .xctest:
            computed = K.testValue
        }
        // Phase 3: locked install with double-check. If a racing caller won,
        // return its value so first-resolution semantics stay deterministic.
        return cache.withLock { entries in
            if let cached = entries[cacheKey] as? K.Value {
                return cached
            }
            entries[cacheKey] = computed
            return computed
        }
    }

    @usableFromInline
    static func resolveTest<K: TestDependencyKey>(_ keyType: K.Type) -> K.Value {
        let context = IssueContext.current
        let cacheKey = CacheKey(id: ObjectIdentifier(K.self), context: context)
        if let cached = cache.withLock({ $0[cacheKey] as? K.Value }) {
            return cached
        }
        let computed: K.Value
        switch context {
        case .preview:
            computed = K.previewValue
        case .runtime, .swiftTesting, .xctest:
            computed = K.testValue
        }
        return cache.withLock { entries in
            if let cached = entries[cacheKey] as? K.Value {
                return cached
            }
            entries[cacheKey] = computed
            return computed
        }
    }

    // MARK: - Test reset

    /// Wipes the process-wide resolution cache. **Test-only**; never call
    /// from production code. Use this at the top of a test-suite setup that
    /// installs new live or preview defaults via ``prepareDependencies(_:)``,
    /// or from teardown when subsequent tests need to observe a clean state.
    @usableFromInline
    package static func _resetCacheForTesting() {
        cache.withLock { $0.removeAll() }
    }
}

