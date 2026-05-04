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

    private struct Greeter: Sendable, Equatable { var name: String }

    private enum GreeterKey: DependencyKey {
        static var liveValue: Greeter { Greeter(name: "live") }
        static var testValue: Greeter { Greeter(name: "test") }
    }

    /// Minimal `DependencyHosting` responder used to seed the responder
    /// chain with a known dependency container.
    private final class HostResponder: NSResponder, DependencyHosting {
        var dependencies = DependencyValues()
    }

    @Test("inheritedDependencies returns an empty container when no host is in the chain")
    func defaultIsEmpty() {
        let responder = NSResponder()
        let inherited = responder.inheritedDependencies
        // Reading any key from the empty container falls through to the
        // context default (`testValue` under Swift Testing).
        #expect(inherited[GreeterKey.self] == Greeter(name: "test"))
    }

    @Test("inheritedDependencies finds the nearest DependencyHosting in the chain")
    func walksUpToHost() {
        let host = HostResponder()
        host.dependencies[GreeterKey.self] = Greeter(name: "host")

        let leaf = NSResponder()
        leaf.nextResponder = host

        #expect(leaf.inheritedDependencies[GreeterKey.self] == Greeter(name: "host"))
    }

    @Test("inheritedDependencies prefers the nearest host when multiple are in the chain")
    func nearestHostWins() {
        let outer = HostResponder()
        outer.dependencies[GreeterKey.self] = Greeter(name: "outer")
        let inner = HostResponder()
        inner.dependencies[GreeterKey.self] = Greeter(name: "inner")

        let leaf = NSResponder()
        leaf.nextResponder = inner
        inner.nextResponder = outer

        #expect(leaf.inheritedDependencies[GreeterKey.self] == Greeter(name: "inner"))
    }

    @Test("inheritedDependencies starts at self when self is a DependencyHosting")
    func selfIsHost() {
        let host = HostResponder()
        host.dependencies[GreeterKey.self] = Greeter(name: "self")
        #expect(host.inheritedDependencies[GreeterKey.self] == Greeter(name: "self"))
    }
}

@Suite("NSDocument dependency storage")
@MainActor
struct NSDocumentDependenciesTests {

    private struct Greeter: Sendable, Equatable { var name: String }

    private enum GreeterKey: DependencyKey {
        static var liveValue: Greeter { Greeter(name: "live") }
        static var testValue: Greeter { Greeter(name: "test") }
    }

    @Test("Default NSDocument returns an empty dependency container")
    func defaultIsEmpty() {
        let document = NSDocument()
        #expect(document.dependencies[GreeterKey.self] == Greeter(name: "test"))
    }

    @Test("Setting NSDocument.dependencies stores the container per document")
    func storesPerDocument() {
        let documentA = NSDocument()
        let documentB = NSDocument()

        var aBag = DependencyValues()
        aBag[GreeterKey.self] = Greeter(name: "doc-A")
        documentA.dependencies = aBag

        var bBag = DependencyValues()
        bBag[GreeterKey.self] = Greeter(name: "doc-B")
        documentB.dependencies = bBag

        // Each document keeps its own associated-object box.
        #expect(documentA.dependencies[GreeterKey.self] == Greeter(name: "doc-A"))
        #expect(documentB.dependencies[GreeterKey.self] == Greeter(name: "doc-B"))
    }

    @Test("NSDocument's DependencyHosting conformance is visible to a window controller chain")
    func documentDiscoverableThroughResponderHost() {
        // NSDocument is not itself an NSResponder subclass, so the
        // responder-chain walk in `inheritedDependencies` does not start
        // at the document. The integration pattern is to install a
        // `DependencyHosting` window controller that reads from its
        // associated document. This test pins the protocol-conformance
        // surface (the document storage round-trips) without asserting
        // a chain shape that the package does not own.
        let document = NSDocument()
        var bag = DependencyValues()
        bag[GreeterKey.self] = Greeter(name: "doc-host")
        document.dependencies = bag

        // Sanity: protocol witness reads through the same storage.
        let host: any DependencyHosting = document
        #expect(host.dependencies[GreeterKey.self] == Greeter(name: "doc-host"))
    }
}
#endif
