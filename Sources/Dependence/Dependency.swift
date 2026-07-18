//
//  Dependency.swift
//  Dependence
//
//  The `@Dependency(\.foo)` property wrapper.
//

import Foundation
import Synchronization

#if canImport(SwiftUI)
    import SwiftUI
#endif

/// Reads a dependency value from the active ``DependencyValues``.
///
/// Two construction forms:
///
/// ```swift
/// @Dependency(\.apiClient)        var api
/// @Dependency(test: APIClient.self) var api  // interface-only modules
/// ```
///
/// The first uses a `KeyPath<DependencyValues, Value>` — this is the
/// canonical form because it picks up extensions declared via
/// `@DependencyEntry`. The second form is reserved for interface-only
/// `TestDependencyKey` lookups where no key path is in scope.
///
/// Inside SwiftUI views, `@Dependency` is also a `DynamicProperty`: it reads
/// from `@Environment(\.dependencies)` first, falling back to the TaskLocal
/// container. This means subtree overrides via `.dependencies { … }` are
/// honored by the view tree's normal invalidation rules — no parallel system.
///
/// The SwiftUI environment is only consulted when SwiftUI actually drives the
/// wrapper (i.e. when it is attached to a `View` / `ViewModifier`). When the
/// wrapper lives on a non-View host such as an `@Observable` class, SwiftUI
/// never invokes ``DynamicProperty/update()`` and the environment is never
/// touched — avoiding the runtime warning
/// "Accessing Environment<…>'s value outside of being installed on a View".
/// Non-View hosts always resolve via the `@TaskLocal`-bound container, which
/// is what ``withDependencies(_:operation:)-(_,_)`` mutates.
@propertyWrapper
public struct Dependency<Value>: Sendable {
    /// Resolves the value out of a container.
    ///
    /// Both construction forms (key path, interface-only key type) reduce to
    /// "read through the active container", so a single stored closure
    /// replaces the former two-case enum whose payloads were identical —
    /// one switch less on every read.
    @usableFromInline
    let read: @Sendable (DependencyValues) -> Value

    #if canImport(SwiftUI)
        /// Stored `@Environment` read.
        ///
        /// Only ever accessed from `update()`, where SwiftUI guarantees the
        /// wrapper is properly installed on a View. We never read this from
        /// `wrappedValue` — doing so off-View would emit the SwiftUI runtime
        /// warning and return the default value anyway.
        @Environment(\.dependencies)
        @usableFromInline
        var _environmentValues: DependencyValues

        /// Reference cell shared across copies of this `Dependency` value.
        ///
        /// `update()` writes the latest SwiftUI environment snapshot here;
        /// `wrappedValue` reads it. When the wrapper is on a non-View host
        /// (`update()` is never invoked), the cell stays `nil` and the SwiftUI
        /// environment is bypassed entirely.
        @usableFromInline
        let _environmentSnapshot: EnvironmentSnapshot = .init()

        /// Heap cell for the SwiftUI environment snapshot.
        ///
        /// Writes happen from SwiftUI's MainActor-bound view-evaluation pass
        /// (`update()`); reads happen from `wrappedValue` on whichever isolation
        /// the caller runs on. We synchronise through `Locked` so the
        /// `Optional<DependencyValues>` discriminator and the dictionary's COW
        /// pointer always publish atomically — Swift 6's memory model does not
        /// guarantee atomicity for plain stored properties even on aligned
        /// pointer-sized values. The lock is uncontended on the hot path
        /// (single-writer / many-reader) and the cost is negligible compared to
        /// the dictionary lookup that follows.
        @usableFromInline
        final class EnvironmentSnapshot: Sendable {
            @usableFromInline
            let values: Mutex<DependencyValues?> = Mutex(nil)

            /// `true` once ``Dependency/update()`` has stored a snapshot.
            ///
            /// Gates the Mutex read in `wrappedValue`: wrappers on non-View
            /// hosts (SwiftUI never drives `update()`) skip the lock entirely
            /// on every read. Relaxed ordering is fine — the flag is monotonic
            /// and only decides *whether* to take the Mutex; the snapshot data
            /// itself is transferred under the Mutex.
            @usableFromInline
            let hasValue = Atomic<Bool>(false)

            @usableFromInline
            init() {}
        }
    #endif

    /// Resolve the value at access time from the active container.
    ///
    /// The resolution order is:
    /// 1. SwiftUI `@Environment(\.dependencies)` if SwiftUI has driven this
    ///    wrapper (i.e. `update()` has run) **and** the captured container
    ///    actually carries overrides — for views inside a
    ///    `.dependencies { … }` subtree.
    /// 2. The `@TaskLocal`-bound ``DependencyValues/_current`` if it carries
    ///    explicit overrides — a ``withDependencies(_:operation:)-(_,_)``
    ///    block in scope always wins.
    /// 3. The top of the SwiftUI subtree stack — for non-View hosts (e.g.
    ///    `@Observable` view models) inside a `.dependencies { … }` subtree
    ///    that don't run `update()`.
    /// 4. The empty `_current`, which falls through to each key's
    ///    `liveValue`/`previewValue`/`testValue`.
    public var wrappedValue: Value {
        #if canImport(SwiftUI)
            // Only consult the snapshot Mutex when SwiftUI has ever driven
            // `update()` for this wrapper — non-View hosts pay a single relaxed
            // load instead of a lock acquisition per read.
            let snapshot: DependencyValues? =
                _environmentSnapshot.hasValue.load(ordering: .relaxed)
                ? _environmentSnapshot.values.withLock { $0 }
                : nil
            let active = DependencyValues.resolveActive(environmentSnapshot: snapshot)
        #else
            let active = DependencyValues.resolveActive(environmentSnapshot: nil)
        #endif
        return read(active)
    }

    /// Construct from a key path — the canonical form.
    ///
    /// `KeyPath` is a generic class without an unconditional `Sendable`
    /// conformance in Swift 6, but reading through one is a pure function of
    /// immutable data. We wrap it in an `UncheckedSendable` box for the
    /// closure capture; reads through the key path remain thread-safe.
    public init(_ keyPath: KeyPath<DependencyValues, Value>) {
        let box = UncheckedSendable(keyPath)
        self.read = { values in values[keyPath: box.value] }
    }

    /// Construct directly from a `TestDependencyKey` type (interface-only).
    public init<K: TestDependencyKey>(test keyType: K.Type) where K.Value == Value {
        self.read = { values in values[test: K.self] }
    }
}

#if canImport(SwiftUI)
    extension Dependency: DynamicProperty {
        /// Called by SwiftUI on every view-evaluation pass on a `View` host.
        ///
        /// Capturing the environment here — and **only** here — makes the
        /// SwiftUI subtree-override path work for views without paying for it
        /// (or warning about it) when the wrapper lives on a non-View host
        /// such as an `@Observable` class.
        public mutating func update() {
            let snapshot = _environmentValues
            _environmentSnapshot.values.withLock { $0 = snapshot }
            _environmentSnapshot.hasValue.store(true, ordering: .relaxed)
        }
    }
#endif
