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
@MainActor
public protocol DependencyHosting: AnyObject {
    /// The dependency container for `self` and its responder descendants.
    var dependencies: DependencyValues { get set }
}

extension NSResponder {
    /// The active `DependencyValues` for this responder, found by walking
    /// `nextResponder` until a `DependencyHosting` is reached. Falls back to
    /// an empty container if the chain ends without a host.
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
