//
//  DependencyClientMacro.swift
//  DependenceMacrosPlugin
//
//  Implementation of `@DependencyClient`. Synthesizes a memberwise init that
//  defaults every closure-typed property to a closure that reports an issue
//  and throws/returns an `unimplemented` value, plus a static
//  `unimplemented` value when every property has a default.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public enum DependencyClientMacro {}

private struct ClientProperty {
    let name: String
    let type: TypeSyntax
    let isClosure: Bool
    let isThrowing: Bool
    let returnText: String
    let parameterCount: Int
    /// Original syntax node for emitting diagnostics anchored at the property.
    let syntax: VariableDeclSyntax
}

extension DependencyClientMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: declaration, message: DependenceDiagnostic.dependencyClientRequiresStruct))
            return []
        }

        // Mirror the struct's access level on the synthesized members. The
        // generated `init` and `static var unimplemented` need to be at least
        // as visible as the struct itself; matching the struct's modifier
        // exactly is the least surprising spelling.
        let accessLevel = accessLevelKeyword(for: structDecl)

        var properties: [ClientProperty] = []
        for member in structDecl.memberBlock.members {
            guard
                let variable = member.decl.as(VariableDeclSyntax.self),
                variable.bindingSpecifier.tokenKind == .keyword(.var),
                let binding = variable.bindings.first,
                let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                let typeAnnotation = binding.typeAnnotation
            else { continue }
            if binding.accessorBlock != nil { continue }

            let type = typeAnnotation.type
            let function = (type.as(AttributedTypeSyntax.self)?.baseType ?? type)
                .as(FunctionTypeSyntax.self)

            if let function {
                let isThrowing = function.effectSpecifiers?.throwsClause != nil
                let returnText = function.returnClause.type.trimmedDescription
                let isVoid = returnText == "Void" || returnText == "()"
                if !isThrowing && !isVoid {
                    // Diagnose: the synthesized default has nowhere to route
                    // a recoverable failure — it must trap. Authors who want
                    // soft-fail behaviour should mark the closure `throws`.
                    context.diagnose(Diagnostic(
                        node: variable,
                        message: DependenceDiagnostic.dependencyClientNonThrowingNonVoidClosure(
                            name: identifier.text,
                            returnType: returnText
                        )
                    ))
                }
                properties.append(.init(
                    name: identifier.text,
                    type: type,
                    isClosure: true,
                    isThrowing: isThrowing,
                    returnText: returnText,
                    parameterCount: function.parameters.count,
                    syntax: variable
                ))
            } else {
                properties.append(.init(
                    name: identifier.text,
                    type: type,
                    isClosure: false,
                    isThrowing: false,
                    returnText: type.trimmedDescription,
                    parameterCount: 0,
                    syntax: variable
                ))
            }
        }

        let initParams = properties.map { property -> String in
            let typeText = property.type.trimmedDescription
            if property.isClosure {
                let escapingType: String
                if typeText.contains("@escaping") {
                    escapingType = typeText
                } else {
                    escapingType = "@escaping \(typeText)"
                }
                return "\(property.name): \(escapingType) = \(unimplementedClosureLiteral(for: property))"
            } else {
                return "\(property.name): \(typeText)"
            }
        }.joined(separator: ", ")

        let initAssignments = properties
            .map { "self.\($0.name) = \($0.name)" }
            .joined(separator: "\n        ")

        let accessPrefix = accessLevel.map { "\($0) " } ?? ""
        // `nonisolated` is always emitted so the synthesized members don't
        // pick up the surrounding type's actor isolation. This matters in
        // modules built with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
        // (Xcode 26+ default-isolation knob): without it, the synthesized
        // `init` is inferred `@MainActor` and any
        // `nonisolated static let preview = Self(...)` site fails to
        // compile. The witness is conceptually Sendable — its init only
        // assigns Sendable closures to stored properties — so isolating it
        // to any actor would be incorrect anyway.
        let memberPrefix = "nonisolated \(accessPrefix)"

        let initDecl: DeclSyntax =
            """
            \(raw: memberPrefix)init(\(raw: initParams)) {
                \(raw: initAssignments)
            }
            """

        if properties.allSatisfy({ $0.isClosure }) {
            let unimplementedDecl: DeclSyntax =
                """
                \(raw: memberPrefix)static var unimplemented: Self { Self() }
                """
            return [initDecl, unimplementedDecl]
        }
        return [initDecl]
    }
}

/// Returns the textual access-level keyword the synthesized members should
/// adopt, matching the struct's own modifier. A `nil` result means "inherit
/// the file-default", same as writing nothing.
private func accessLevelKeyword(for structDecl: StructDeclSyntax) -> String? {
    for modifier in structDecl.modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public): return "public"
        case .keyword(.package): return "package"
        case .keyword(.internal): return "internal"
        case .keyword(.fileprivate): return "fileprivate"
        // `private` on a struct still allows file-scope members; mirror as
        // `fileprivate` so the synthesized members remain reachable wherever
        // the struct is reachable.
        case .keyword(.private): return "fileprivate"
        default: continue
        }
    }
    return nil
}

private func unimplementedClosureLiteral(for property: ClientProperty) -> String {
    let placeholders = property.parameterCount == 0
        ? ""
        : Array(repeating: "_", count: property.parameterCount).joined(separator: ", ") + " in "
    let report = #"Dependence.reportIssue("unimplemented: \#(property.name)")"#
    let body: String
    if property.isThrowing {
        body = "\(report); throw Dependence.DependencyError.unimplemented(\"\(property.name)\")"
    } else if property.returnText == "Void" || property.returnText == "()" {
        body = report
    } else {
        // Non-throwing, non-Void: trap with a clear message. Authors who
        // want soft failures should mark the closure `throws` (a warning
        // diagnostic above flags this case).
        body = "\(report); fatalError(\"unimplemented closure '\(property.name)' returns \(property.returnText); mark it 'throws' to surface as a test failure instead\")"
    }
    return "{ \(placeholders)\(body) }"
}
