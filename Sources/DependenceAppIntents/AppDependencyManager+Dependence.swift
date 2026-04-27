//
//  AppDependencyManager+Dependence.swift
//  DependenceAppIntents
//
//  Bridge between Apple's `AppDependencyManager` (App Intents) and
//  Dependence's `DependencyValues`. Keeps a single source of truth: the
//  values prepared via ``prepareDependencies(_:)`` at the composition root
//  are surfaced to App Intents' framework `@Dependency` (i.e.
//  `AppDependency<Value>`) without manual duplicate registration.
//

#if canImport(AppIntents)
import AppIntents
import Dependence

extension AppDependencyManager {

    /// Bridge a Dependence-managed value to App Intents' dependency container.
    ///
    /// Registers a provider with `AppDependencyManager` that resolves through
    /// ``DependencyValues/current`` on each access. After this call, an
    /// intent's framework `@Dependency var foo: Foo` and an in-app
    /// `@Dependency(\.foo)` (Dependence's wrapper) read the same value — the
    /// one prepared at the composition root.
    ///
    /// Why this exists: AppIntents has its own dependency manager
    /// (`AppDependencyManager`) and its own property wrapper
    /// (`AppDependency`), and the framework's bootstrap fires only when the
    /// system dispatches an intent. Code that uses `AppDependency` therefore
    /// can't read values prepared exclusively through Dependence — and code
    /// that uses Dependence can't see values registered exclusively through
    /// `AppDependencyManager.shared.add(dependency:)`. This bridge makes the
    /// two containers agree on a single instance per type.
    ///
    /// Call after ``prepareDependencies(_:)`` so the cache is populated. The
    /// provider closure is captured lazily, so registration order between
    /// the two containers is flexible — as long as both are wired before the
    /// first intent runs.
    ///
    /// ```swift
    /// import AppIntents
    /// import Dependence
    /// import DependenceAppIntents
    ///
    /// @main struct MyApp: App {
    ///     init() {
    ///         prepareDependencies {
    ///             $0.router = Router()
    ///             $0.presetService = PresetService()
    ///         }
    ///         AppDependencyManager.shared.bridge(\.router)
    ///         AppDependencyManager.shared.bridge(\.presetService)
    ///     }
    ///     // ...
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A keypath into ``DependencyValues`` whose value is
    ///     `Sendable`. The keypath itself is treated as conceptually
    ///     immutable (Swift 6 doesn't grant `KeyPath` an unconditional
    ///     `Sendable` conformance) and crossed into the `@Sendable` provider
    ///     via an internal unchecked-Sendable box.
    ///   - key: Optional disambiguation key, mirroring
    ///     `add(key:dependency:)`. Use when bridging multiple values of the
    ///     same type.
    public func bridge<Value: Sendable>(
        _ keyPath: KeyPath<DependencyValues, Value>,
        key: AnyHashable? = nil
    ) {
        let box = UncheckedSendable(keyPath)
        // `add(dependency:)` is `@autoclosure @escaping @Sendable () -> Value`,
        // so the expression below becomes the lazy provider AppIntents calls
        // each time the dependency is resolved.
        add(key: key, dependency: DependencyValues.current[keyPath: box.value])
    }
}

extension AppDependencyManager {

    /// Bridge an interface-only Dependence key to App Intents.
    ///
    /// Companion to ``bridge(_:key:)`` for modular setups where the live
    /// implementation lives in a different module than the protocol — i.e.
    /// values registered with `TestDependencyKey` and read via
    /// `@Dependency(test: K.self)`. The provider resolves through
    /// `DependencyValues.current[test:]`, picking up
    /// ``prepareDependencies(_:)`` overrides for the same key type.
    ///
    /// - Parameters:
    ///   - keyType: The interface key. The bridged value is whatever the
    ///     active ``DependencyValues`` resolves for `keyType` at access
    ///     time.
    ///   - key: Optional disambiguation key for AppIntents.
    public func bridge<K: TestDependencyKey>(
        test keyType: K.Type,
        key: AnyHashable? = nil
    ) where K.Value: Sendable {
        add(key: key, dependency: DependencyValues.current[test: K.self])
    }
}
#endif
