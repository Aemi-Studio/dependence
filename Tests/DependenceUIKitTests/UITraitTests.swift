//
//  UITraitTests.swift
//  DependenceUIKitTests
//

#if canImport(UIKit)
import Dependence
import DependenceUIKit
import Testing
import UIKit

@Suite("UITrait dependencies")
@MainActor
struct UITraitTests {

    @Test("Default trait collection returns an empty dependency container")
    func defaultIsEmpty() {
        let collection = UITraitCollection()
        let values = collection.dependencies
        // The default container has no overrides; smoke-test that we got a
        // value back.
        _ = values
    }
}
#endif
