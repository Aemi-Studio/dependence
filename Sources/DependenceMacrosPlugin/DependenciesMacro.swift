//
//  DependenciesMacro.swift
//  DependenceMacrosPlugin
//
//  Implementation of `@Dependencies(\.foo, \.bar)`. For each key path literal
//  passed in, synthesizes a stored property of the form
//  `@ObservationIgnored @Dependency(\.<name>) private var <name>`.
//
//  Property types are inferred from `Dependency<Value>`'s `wrappedValue`.
//  The macro never attempts to resolve `DependencyValues.<name>`'s declared
//  type — the compiler does that during the post-expansion type-check pass.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public enum DependenciesMacro {}

extension DependenciesMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            case let .argumentList(arguments) = node.arguments,
            !arguments.isEmpty
        else {
            context.diagnose(Diagnostic(node: node, message: DependenceDiagnostic.dependenciesRequiresKeyPathArgument))
            return []
        }

        var decls: [DeclSyntax] = []
        var seen: Set<String> = []
        for argument in arguments {
            guard let keyPath = argument.expression.as(KeyPathExprSyntax.self) else {
                context.diagnose(Diagnostic(node: argument.expression, message: DependenceDiagnostic.dependenciesRequiresKeyPathArgument))
                continue
            }
            guard let name = trailingPropertyName(of: keyPath) else {
                context.diagnose(Diagnostic(node: keyPath, message: DependenceDiagnostic.dependenciesKeyPathMissingPropertyComponent))
                continue
            }
            // Skip duplicates silently — re-stamping the same property would
            // produce a redeclaration error from the compiler anyway, but a
            // graceful skip keeps the diagnostic story focused on real bugs.
            guard seen.insert(name).inserted else { continue }

            decls.append(
                """
                @ObservationIgnored
                @Dependence.Dependency(\\.\(raw: name)) private var \(raw: name)
                """
            )
        }
        return decls
    }
}

/// Extracts the single trailing property identifier from a key path literal:
/// `\.apiClient` -> `"apiClient"`. Returns `nil` if the literal has no
/// property component (e.g. `\.self`) or has multiple components
/// (e.g. `\.network.client`) — both unsupported in this macro because the
/// synthesized property name would be ambiguous.
private func trailingPropertyName(of keyPath: KeyPathExprSyntax) -> String? {
    let components = keyPath.components
    guard components.count == 1 else { return nil }
    guard
        let property = components.first?.component.as(KeyPathPropertyComponentSyntax.self)
    else { return nil }
    return property.declName.baseName.text
}
