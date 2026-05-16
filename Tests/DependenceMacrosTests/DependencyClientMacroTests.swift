//
//  DependencyClientMacroTests.swift
//  DependenceMacrosTests
//
//  Direct-expansion tests for `@DependencyClient`. Bypasses
//  `assertMacroExpansion` because that helper uses `XCTFail`, which does not
//  surface failures through Swift Testing's `@Test`/`#expect` machinery —
//  mismatched expansions would silently pass. Driving the macro plugin
//  directly with `BasicMacroExpansionContext` lets `#expect` see real
//  pass/fail outcomes.
//

import DependenceMacrosPlugin
import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing

@Suite("@DependencyClient expansion")
struct DependencyClientMacroTests {

    // MARK: Helpers

    /// Expands `@DependencyClient` on `source` and returns the synthesized
    /// declarations as a single string (one decl per line, trimmed).
    private func expand(_ source: String) throws -> String {
        let file = Parser.parse(source: source)
        let context = BasicMacroExpansionContext(
            lexicalContext: [],
            expansionDiscriminator: "DependencyClientMacroTests",
            sourceFiles: [file: .init(moduleName: "TestModule", fullFilePath: "test.swift")]
        )
        let structDecl = try #require(
            file.statements
                .compactMap { $0.item.as(StructDeclSyntax.self) }
                .first
        )
        let attribute = try #require(structDecl.attributes.first?.as(AttributeSyntax.self))
        let decls = try DependencyClientMacro.expansion(
            of: attribute,
            providingMembersOf: structDecl,
            conformingTo: [],
            in: context
        )
        return decls.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
    }

    // MARK: Tests

    @Test("Synthesized init is marked nonisolated")
    func initIsNonisolated() throws {
        // The `nonisolated` modifier is critical for modules that set
        // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without it, the
        // synthesized init inherits MainActor isolation from the surrounding
        // type and any `nonisolated static let preview = Self(...)` site
        // fails to compile because it would be calling a `@MainActor` init
        // from a nonisolated context.
        let expansion = try expand(
            """
            @DependencyClient
            public struct APIClient: Sendable {
                public var fetch: @Sendable (URL) async throws -> Data
                public var cancel: @Sendable () -> Void
            }
            """
        )
        #expect(expansion.contains("nonisolated public init("))
    }

    @Test("Synthesized static unimplemented witness is marked nonisolated")
    func unimplementedIsNonisolated() throws {
        let expansion = try expand(
            """
            @DependencyClient
            public struct APIClient: Sendable {
                public var fetch: @Sendable (URL) async throws -> Data
                public var cancel: @Sendable () -> Void
            }
            """
        )
        #expect(expansion.contains("nonisolated public static var unimplemented"))
    }

    @Test("Init nonisolated modifier is emitted even when no static witness is generated")
    func nonisolatedInitWithRequiredProperty() throws {
        // With a non-closure stored property, no `static var unimplemented`
        // is synthesized, but the init still needs to be nonisolated so
        // callers in any isolation can construct the witness.
        let expansion = try expand(
            """
            @DependencyClient
            public struct Mixed: Sendable {
                public var name: String
                public var run: @Sendable () -> Void
            }
            """
        )
        #expect(expansion.contains("nonisolated public init("))
        #expect(!expansion.contains("static var unimplemented"))
    }

    @Test("Nonisolated modifier is preserved across access levels")
    func internalAccessLevel() throws {
        let expansion = try expand(
            """
            @DependencyClient
            struct Internal: Sendable {
                var ping: @Sendable () -> Void
            }
            """
        )
        // Internal access — no `public`/`internal` keyword expected, but the
        // `nonisolated` keyword must still lead both decls.
        #expect(expansion.contains("nonisolated init("))
        #expect(expansion.contains("nonisolated static var unimplemented"))
    }
}
