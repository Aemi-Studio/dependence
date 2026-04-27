//
//  NSResponderTests.swift
//  DependenceAppKitTests
//

#if canImport(AppKit)
import AppKit
import Dependence
import DependenceAppKit
import Testing

@Suite("AppKit responder chain")
@MainActor
struct NSResponderTests {

    @Test("inheritedDependencies returns an empty container when no host is in the chain")
    func defaultIsEmpty() {
        let responder = NSResponder()
        _ = responder.inheritedDependencies
    }
}
#endif
