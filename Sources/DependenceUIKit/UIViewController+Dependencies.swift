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
