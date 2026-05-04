//
//  UITraitTests.swift
//  DependenceUIKitTests
//
//  UIKit trait-chain integration. iOS 26+ promotes `UITraitDefinition` and
//  `traitOverrides` to first-class storage, which is what
//  `DependenceUIKit.DependenceTrait` plugs into. These tests verify
//  override application, parent→child inheritance through the UIKit view
//  controller hierarchy, and `UIView.dependencies(_:)`.
//

#if canImport(UIKit)
import Dependence
import DependenceUIKit
import Testing
import UIKit

@Suite("UITrait dependencies")
@MainActor
struct UITraitTests {

    private struct Greeter: Sendable, Equatable { var name: String }

    private enum GreeterKey: DependencyKey {
        static var liveValue: Greeter { Greeter(name: "live") }
        static var testValue: Greeter { Greeter(name: "test") }
    }

    @Test("Default trait collection returns an empty dependency container")
    func defaultIsEmpty() {
        let collection = UITraitCollection()
        // Reading any key returns the context default — the empty container
        // falls through to the cached `testValue`.
        #expect(collection.dependencies[GreeterKey.self] == Greeter(name: "test"))
    }

    @Test("UIViewController.dependencies stores the override in traitOverrides")
    func viewControllerDependenciesStoresOverride() {
        let viewController = UIViewController()
        viewController.dependencies {
            $0[GreeterKey.self] = Greeter(name: "vc-scope")
        }

        // The trait override is present on the VC.
        let stored = viewController.traitOverrides.dependencies
        #expect(stored[GreeterKey.self] == Greeter(name: "vc-scope"))
    }

    @Test("Child view controllers inherit dependencies from their parent")
    func childInheritsParentDependencies() {
        let parent = UIViewController()
        let child = UIViewController()

        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.didMove(toParent: parent)

        parent.dependencies {
            $0[GreeterKey.self] = Greeter(name: "from-parent")
        }

        // Force the trait collection to propagate to the child. Adding the
        // child view to the parent's view triggers UIKit's trait inheritance
        // automatically when the hierarchy is in a window or laid out.
        parent.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.view.layoutIfNeeded()
        child.view.layoutIfNeeded()

        // The child's traitCollection inherits from its parent VC's trait
        // overrides through the standard UIKit trait propagation chain.
        #expect(child.traitCollection.dependencies[GreeterKey.self] == Greeter(name: "from-parent"))
    }

    @Test("Child view controller's own override shadows the parent's")
    func childOverrideShadowsParent() {
        let parent = UIViewController()
        let child = UIViewController()

        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.didMove(toParent: parent)

        parent.dependencies {
            $0[GreeterKey.self] = Greeter(name: "parent")
        }
        child.dependencies {
            $0[GreeterKey.self] = Greeter(name: "child")
        }

        parent.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.view.layoutIfNeeded()
        child.view.layoutIfNeeded()

        #expect(child.traitCollection.dependencies[GreeterKey.self] == Greeter(name: "child"))
        #expect(parent.traitCollection.dependencies[GreeterKey.self] == Greeter(name: "parent"))
    }

    @Test("UIView.dependencies(_:) writes the override on the view's trait overrides")
    func viewDependenciesStoresOverride() {
        let view = UIView()
        view.dependencies {
            $0[GreeterKey.self] = Greeter(name: "view-scope")
        }
        #expect(view.traitOverrides.dependencies[GreeterKey.self] == Greeter(name: "view-scope"))
    }
}
#endif
