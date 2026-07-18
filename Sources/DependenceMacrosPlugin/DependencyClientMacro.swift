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

// TODO: deferred edge cases (bounded scope for v1.1.0; each currently falls
// through to "not a closure -> required init parameter", which is safe but
// unrefined):
// - implicitly-unwrapped closure types (`(() -> Void)!`)
// - closure typealiases (the macro sees the nominal type, not the function
//   shape, so no unimplemented default is synthesized)
// - property wrappers / `lazy` on members
// - `willSet`/`didSet` observers (treated as stored; observers preserved)
public enum DependencyClientMacro {}

private struct ClientProperty {
    let name: String
    let type: TypeSyntax
    let isClosure: Bool
    let isOptionalClosure: Bool
    let isThrowing: Bool
    let returnText: String
    let parameterCount: Int
    /// `false` when the member must be supplied at every call site (e.g. a
    /// typed-throws closure whose default cannot be synthesized).
    let hasSynthesizedDefault: Bool
}

/// Peels a (possibly optional, attributed, or parenthesized) closure type
/// down to its `FunctionTypeSyntax`.
///
/// Handles the shapes `@Sendable (A) -> B`, `((A) -> B)?`, and
/// `(@Sendable (A) -> B)?` — the optional forms wrap the function in a
/// single-element tuple.
private func closureShape(of type: TypeSyntax) -> (function: FunctionTypeSyntax, isOptional: Bool)? {
    var working = type
    var isOptional = false
    if let optional = working.as(OptionalTypeSyntax.self) {
        isOptional = true
        working = optional.wrappedType
    }
    if let attributed = working.as(AttributedTypeSyntax.self) {
        working = attributed.baseType
    }
    if let tuple = working.as(TupleTypeSyntax.self),
        tuple.elements.count == 1,
        let onlyElement = tuple.elements.first,
        onlyElement.firstName == nil
    {
        working = onlyElement.type
        if let attributed = working.as(AttributedTypeSyntax.self) {
            working = attributed.baseType
        }
    }
    guard let function = working.as(FunctionTypeSyntax.self) else { return nil }
    return (function, isOptional)
}

/// Thrown-type spellings the synthesized `DependencyError.unimplemented`
/// default can satisfy.
private let synthesizableThrownTypes: Set<String> = [
    "Error", "any Error", "Swift.Error", "any Swift.Error",
    "DependencyError", "Dependence.DependencyError",
]

extension DependencyClientMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(node: declaration, message: DependenceDiagnostic.dependencyClientRequiresStruct))
            return []
        }

        // Mirror the struct's access level on the synthesized members. The
        // generated `init` and `static var unimplemented` need to be at least
        // as visible as the struct itself; matching the struct's modifier
        // exactly is the least surprising spelling.
        let accessLevel = accessLevelKeyword(for: structDecl)

        var properties: [ClientProperty] = []
        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            // Multi-binding declarations (`var a, b: T`) put the type
            // annotation on the last binding only; synthesizing from the
            // first silently dropped the rest and produced an opaque
            // "missing stored property" error inside the expansion.
            guard variable.bindings.count == 1, let binding = variable.bindings.first else {
                context.diagnose(
                    Diagnostic(node: variable, message: DependenceDiagnostic.dependencyClientMultipleBindings))
                continue
            }
            // Computed properties don't participate in memberwise inits.
            if binding.accessorBlock != nil { continue }
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
                continue
            }
            if variable.bindingSpecifier.tokenKind == .keyword(.let) {
                // A `let` with an inline default is fine (already
                // initialized); a `let` without one cannot be assigned by
                // the synthesized init — previously an opaque failure.
                if binding.initializer == nil {
                    context.diagnose(
                        Diagnostic(
                            node: variable,
                            message: DependenceDiagnostic.dependencyClientLetRequiresInitializer(
                                name: identifier.text
                            )
                        )
                    )
                }
                continue
            }
            guard variable.bindingSpecifier.tokenKind == .keyword(.var),
                let typeAnnotation = binding.typeAnnotation
            else { continue }

            let type = typeAnnotation.type
            guard let (function, isOptional) = closureShape(of: type) else {
                properties.append(
                    ClientProperty(
                        name: identifier.text,
                        type: type,
                        isClosure: false,
                        isOptionalClosure: false,
                        isThrowing: false,
                        returnText: type.trimmedDescription,
                        parameterCount: 0,
                        hasSynthesizedDefault: false
                    )
                )
                continue
            }

            let throwsClause = function.effectSpecifiers?.throwsClause
            let isThrowing = throwsClause != nil
            let returnText = function.returnClause.type.trimmedDescription
            let isVoid = returnText == "Void" || returnText == "()"

            var hasSynthesizedDefault = true
            if !isOptional, let thrownType = throwsClause?.type?.trimmedDescription,
                !synthesizableThrownTypes.contains(thrownType)
            {
                // The synthesized default throws DependencyError.unimplemented,
                // which cannot convert to an arbitrary typed-throws error.
                // Diagnose clearly and make the member a required parameter
                // instead of emitting non-compiling synthesis.
                context.diagnose(
                    Diagnostic(
                        node: variable,
                        message: DependenceDiagnostic.dependencyClientTypedThrowsNeedsDefault(
                            name: identifier.text,
                            thrownType: thrownType
                        )
                    )
                )
                hasSynthesizedDefault = false
            }
            if !isOptional && !isThrowing && !isVoid {
                // Diagnose: the synthesized default has nowhere to route
                // a recoverable failure — it must trap. Authors who want
                // soft-fail behaviour should mark the closure `throws`.
                context.diagnose(
                    Diagnostic(
                        node: variable,
                        message: DependenceDiagnostic.dependencyClientNonThrowingNonVoidClosure(
                            name: identifier.text,
                            returnType: returnText
                        )
                    )
                )
            }
            properties.append(
                ClientProperty(
                    name: identifier.text,
                    type: type,
                    isClosure: true,
                    isOptionalClosure: isOptional,
                    isThrowing: isThrowing,
                    returnText: returnText,
                    parameterCount: function.parameters.count,
                    hasSynthesizedDefault: hasSynthesizedDefault
                )
            )
        }

        let initParams = properties.map { property -> String in
            let typeText = property.type.trimmedDescription
            guard property.isClosure else {
                return "\(property.name): \(typeText)"
            }
            if property.isOptionalClosure {
                // Optional closures are implicitly escaping; `@escaping`
                // would be rejected. The natural default is `nil` — "no
                // handler installed" — mirroring memberwise-init behavior
                // for optional stored properties.
                return "\(property.name): \(typeText) = nil"
            }
            let escapingType: String
            if typeText.contains("@escaping") {
                escapingType = typeText
            } else {
                escapingType = "@escaping \(typeText)"
            }
            guard property.hasSynthesizedDefault else {
                return "\(property.name): \(escapingType)"
            }
            return "\(property.name): \(escapingType) = \(unimplementedClosureLiteral(for: property))"
        }.joined(separator: ", ")

        let initAssignments =
            properties
            .map { "self.\($0.name) = \($0.name)" }
            .joined(separator: "\n    ")

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

        if properties.allSatisfy({ $0.isClosure && $0.hasSynthesizedDefault }) {
            let unimplementedDecl: DeclSyntax =
                """
                \(raw: memberPrefix)static var unimplemented: Self { Self() }
                """
            return [initDecl, unimplementedDecl]
        }
        return [initDecl]
    }
}

/// Returns the textual access-level keyword the synthesized members adopt.
///
/// Matches the struct's own modifier. A `nil` result means "inherit the
/// file-default", same as writing nothing.
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
    let placeholders =
        property.parameterCount == 0
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
        body =
            "\(report); fatalError(\"unimplemented closure '\(property.name)' returns \(property.returnText); mark it 'throws' to surface as a test failure instead\")"
    }
    return "{ \(placeholders)\(body) }"
}
