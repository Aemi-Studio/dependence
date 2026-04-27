//
//  Plugin.swift
//  DependenceMacrosPlugin
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DependenceMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        DependencyEntryMacro.self,
        DependencyClientMacro.self,
        DependenciesMacro.self,
    ]
}
