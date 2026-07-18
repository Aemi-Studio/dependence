//
//  DependencyEntryMacro.swift
//  DependenceMacrosPlugin
//
//  Implementation of `@DependencyEntry`. Mirrors SwiftUI's `@Entry` macro:
//  given a `var foo = expr` (with optional explicit type), generates a
//  private `DependencyKey`-conforming struct holding the live value and
//  rewrites the property as a get/set pair routed through the key.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public enum DependencyEntryMacro {}

extension DependencyEntryMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard
            let variable = declaration.as(VariableDeclSyntax.self),
            let binding = variable.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
        else {
            return []
        }
        guard variable.bindingSpecifier.tokenKind == .keyword(.var) else {
            context.diagnose(
                Diagnostic(node: variable.bindingSpecifier, message: DependenceDiagnostic.dependencyEntryRequiresVar))
            return []
        }

        // Two forms:
        //
        //   @DependencyEntry var foo: Foo = .live
        //     -> generate a private key __Key_foo with `liveValue = .live`,
        //        accessors route through `self[__Key_foo.self]` (DependencyKey).
        //
        //   @DependencyEntry var foo: Foo
        //     -> no peer key generated; accessors route through an
        //        externally-declared `FooKey: TestDependencyKey` via
        //        `self[test: FooKey.self]`. This is the interface-module
        //        pattern: the live value lives in a separate Impl module.
        guard binding.initializer != nil else {
            guard let typeText = binding.typeAnnotation?.type.trimmedDescription else {
                context.diagnose(
                    Diagnostic(node: variable, message: DependenceDiagnostic.dependencyEntryRequiresInitializer))
                return []
            }
            // The interface-only form points at an externally-declared key
            // type whose name is derived from the property's type. Generic
            // arguments, optionals, `any`/`some` prefixes and other non-
            // identifier characters would produce an invalid Swift name —
            // sanitise them down to a plain identifier.
            let keyName = "\(sanitizedKeyName(from: typeText))Key"
            return [
                """
                get { self[test: \(raw: keyName).self] }
                """,
                """
                set { self[test: \(raw: keyName).self] = newValue }
                """,
            ]
        }
        let keyName = "__Key_\(identifier.text)"
        return [
            """
            get { self[\(raw: keyName).self] }
            """,
            """
            set { self[\(raw: keyName).self] = newValue }
            """,
        ]
    }
}

/// Strip non-identifier characters from a type description and return a name
/// safe to use as a Swift identifier prefix.
///
/// Examples:
/// - `"APIClient"`           → `"APIClient"`
/// - `"any APIClient"`       → `"APIClient"`
/// - `"some APIClient"`      → `"APIClient"`
/// - `"APIClient?"`          → `"APIClient"`
/// - `"Result<Foo, Error>"`  → `"Result_Foo_Error"`
/// - `"[Item]"`              → `"Item"`
private func sanitizedKeyName(from typeText: String) -> String {
    // Strip leading existential / opaque markers and surrounding whitespace.
    // (Foundation isn't linked into the macro plugin, so we hand-roll the
    // trim instead of reaching for `trimmingCharacters(in:)`.)
    var working = Substring(typeText)
    while let first = working.first, first.isWhitespace {
        working = working.dropFirst()
    }
    for prefix in ["any ", "some "] {
        if working.hasPrefix(prefix) {
            working = working.dropFirst(prefix.count)
            while let first = working.first, first.isWhitespace {
                working = working.dropFirst()
            }
        }
    }
    // Replace each disallowed character with `_`, then collapse runs of `_`.
    var result = ""
    var lastWasUnderscore = false
    for scalar in String(working).unicodeScalars {
        let isAllowed =
            (scalar >= "A" && scalar <= "Z")
            || (scalar >= "a" && scalar <= "z")
            || (scalar >= "0" && scalar <= "9")
            || scalar == "_"
        if isAllowed {
            result.unicodeScalars.append(scalar)
            lastWasUnderscore = scalar == "_"
        } else if !lastWasUnderscore && !result.isEmpty {
            result.append("_")
            lastWasUnderscore = true
        }
    }
    // Drop any trailing underscore introduced by the final character being
    // disallowed (e.g. `"Foo?"` → `"Foo_"` → `"Foo"`).
    while result.hasSuffix("_") { result.removeLast() }
    return result.isEmpty ? "Anonymous" : result
}

extension DependencyEntryMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let variable = declaration.as(VariableDeclSyntax.self),
            let binding = variable.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
        else {
            return []
        }
        guard variable.bindingSpecifier.tokenKind == .keyword(.var) else {
            return []
        }

        guard let initializer = binding.initializer?.value.trimmedDescription else {
            // Interface-module form: no initializer, route through an
            // externally-declared `<TypeName>Key`. No peer to generate.
            return []
        }

        // Extra witnesses, when the user spelled `@DependencyEntry(preview:…,
        // test:…)`. These are stamped *into the conformance*, not added in a
        // later extension — the protocol witness table is sealed at conformance
        // declaration, and a `previewValue` added in an extension only changes
        // direct dispatch, not generic `K.previewValue`. Stamping here is the
        // only spelling that lets `IssueContext`-driven resolution see them.
        let preview = labeledArgument(named: "preview", in: node)
        let test = labeledArgument(named: "test", in: node)

        // The enum is emitted `nonisolated` so its witnesses stay nonisolated
        // even in modules built with default isolation MainActor
        // (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). `DependencyKey`
        // inherits `Sendable`, so the conformance cannot be actor-isolated
        // anyway — spelling it out keeps the expansion self-explanatory and
        // future-proof against inference-rule changes.
        //
        // What the macro CANNOT fix: the user's witness expression itself.
        // In a MainActor-default module, `static let live = …` on the witness
        // type is implicitly `@MainActor`, and referencing it from the
        // nonisolated `liveValue` below is a compile error pointing into
        // this expansion. The macro has no visibility into the witness's
        // isolation, so the requirement is documented on `@DependencyEntry`:
        // mark such witness statics `nonisolated`.
        let keyName = "__Key_\(identifier.text)"
        let decl: DeclSyntax
        if let explicitType = binding.typeAnnotation?.type.trimmedDescription {
            var lines: [String] = [
                "static var liveValue: \(explicitType) { \(initializer) }"
            ]
            if let preview {
                lines.append("static var previewValue: \(explicitType) { \(preview) }")
            }
            if let test {
                lines.append("static var testValue: \(explicitType) { \(test) }")
            }
            decl =
                """
                fileprivate nonisolated enum \(raw: keyName): Dependence.DependencyKey {
                    typealias Value = \(raw: explicitType)
                    \(raw: lines.joined(separator: "\n    "))
                }
                """
        } else {
            // Let the type be inferred from the initializer expression.
            // All three witnesses use `let = expr` so associated-type
            // inference flows from the right-hand sides — referencing `Value`
            // in an explicit annotation here would deadlock inference under
            // Swift 6.3+.
            var lines: [String] = [
                "static let liveValue = \(initializer)"
            ]
            if let preview {
                lines.append("static let previewValue = \(preview)")
            }
            if let test {
                lines.append("static let testValue = \(test)")
            }
            decl =
                """
                fileprivate nonisolated enum \(raw: keyName): Dependence.DependencyKey {
                    \(raw: lines.joined(separator: "\n    "))
                }
                """
        }
        return [decl]
    }

    /// Pull the textual expression for a labeled argument off the macro
    /// attribute, e.g. `.preview` from `@DependencyEntry(preview: .preview)`.
    private static func labeledArgument(
        named label: String,
        in node: AttributeSyntax
    ) -> String? {
        guard case .argumentList(let args) = node.arguments else { return nil }
        return
            args
            .first { $0.label?.text == label }?
            .expression
            .trimmedDescription
    }
}
