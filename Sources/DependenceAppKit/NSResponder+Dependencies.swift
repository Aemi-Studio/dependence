//
//  NSResponder+Dependencies.swift
//  DependenceAppKit
//
//  Walks the AppKit responder chain to find the nearest dependency host.
//

#if canImport(AppKit)
    import AppKit
    import Dependence

    /// Conformed by responders (typically a window controller, view controller,
    /// or the application delegate) that act as a dependency host for their
    /// subtree.
    ///
    /// **Asymmetry with the SwiftUI adapter**: SwiftUI's
    /// `View.dependencies(_:)` also publishes overrides to a process-wide
    /// subtree stack so non-View hosts resolve through them. The AppKit adapter
    /// deliberately does **not** — a host's container is only visible by
    /// walking the responder chain (``NSResponder/inheritedDependencies``).
    /// Objects outside the chain (view models, services) should be constructed
    /// under `withDependencies`/`withSnapshotDependencies` with the inherited
    /// container, or read it explicitly.
    @MainActor
    public protocol DependencyHosting: AnyObject {
        /// The dependency container for `self` and its responder descendants.
        var dependencies: DependencyValues { get set }
    }

    extension NSResponder {
        /// The active `DependencyValues` for this responder.
        ///
        /// Found by walking `nextResponder` until a `DependencyHosting` is
        /// reached. Falls back to an empty container if the chain ends
        /// without a host.
        @MainActor
        public var inheritedDependencies: DependencyValues {
            var current: NSResponder? = self
            while let responder = current {
                if let host = responder as? any DependencyHosting {
                    return host.dependencies
                }
                current = responder.nextResponder
            }
            return .init()
        }
    }
#endif
