//
//  UIViewController+Dependencies.swift
//  DependenceUIKit
//

#if canImport(UIKit)
    import Dependence
    import UIKit

    extension UIViewController {
        /// Apply dependency overrides for `self` and its descendants in the
        /// UIKit trait chain.
        ///
        /// ```swift
        /// container.dependencies { $0.apiClient = .mock }
        /// ```
        ///
        /// The closure receives an `inout DependencyValues` initialized to the
        /// values currently inherited from the responder chain. Any mutations
        /// become the new override on `self.traitOverrides`.
        ///
        /// **Asymmetry with the SwiftUI adapter**: SwiftUI's
        /// `View.dependencies(_:)` also publishes the override to a
        /// process-wide subtree stack so non-View hosts (e.g. `@Observable`
        /// view models) resolve through it. The UIKit adapter deliberately does
        /// **not** — the override lives only in the trait collection, which has
        /// well-defined tree scoping and inheritance. Objects that are not part
        /// of the trait environment (view models, services) should be
        /// constructed under `withDependencies`/`withSnapshotDependencies`, or
        /// read `traitCollection.dependencies` explicitly.
        @MainActor
        public func dependencies(_ mutate: (inout DependencyValues) -> Void) {
            var values = traitCollection.dependencies
            mutate(&values)
            traitOverrides.dependencies = values
        }
    }

    extension UIView {
        /// View-level convenience mirror of ``UIViewController.dependencies(_:)``.
        @MainActor
        public func dependencies(_ mutate: (inout DependencyValues) -> Void) {
            var values = traitCollection.dependencies
            mutate(&values)
            traitOverrides.dependencies = values
        }
    }
#endif
