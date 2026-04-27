//
//  UITraitContainer.swift
//  DependenceUIKit
//
//  Bridges `DependencyValues` into the UIKit trait system so subtree
//  overrides work analogously to SwiftUI's `@Environment`. Available on
//  iOS 26+ where `UITraitDefinition` and `traitOverrides` are first-class.
//

#if canImport(UIKit)
import Dependence
import UIKit

/// A `UITraitDefinition` that carries the active `DependencyValues` through
/// the UIKit trait inheritance chain.
///
/// Reading: any `UITraitEnvironment` (views, view controllers, scenes,
/// windows) can ask `traitCollection.dependencies` for the active container.
/// Writing: container view controllers apply overrides via
/// `viewController.traitOverrides.dependencies = ...`.
public struct DependenceTrait: UITraitDefinition {
    public static let defaultValue: DependencyValues = .init()
    public static let affectsColorAppearance: Bool = false
    public static let identifier: String = "com.dependence.UITrait.dependencies"
    public static let name: String = "Dependence.dependencies"
}

extension UITraitCollection {
    /// The active `DependencyValues` resolved through the trait chain.
    ///
    /// Falls back to an empty container if no ancestor has applied an override.
    public var dependencies: DependencyValues {
        self[DependenceTrait.self]
    }
}

extension UIMutableTraits {
    /// Apply or read the trait-scoped `DependencyValues`.
    public var dependencies: DependencyValues {
        get { self[DependenceTrait.self] }
        set { self[DependenceTrait.self] = newValue }
    }
}
#endif
