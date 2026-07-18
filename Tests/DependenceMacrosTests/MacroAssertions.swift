//
//  MacroAssertions.swift
//  DependenceMacrosTests
//
//  Swift-Testing-native macro assertion helper.
//
//  `SwiftSyntaxMacrosTestSupport.assertMacroExpansion` reports through the
//  XCTest bridge, which emits an "XCTest bridging" warning per call when the
//  suite runs under Swift Testing (8 warnings across this target before the
//  migration). The generic-support variant takes an explicit failure
//  handler instead — we route it to `Issue.record`, so failures carry
//  proper Swift Testing source locations and the run is warning-free.
//

import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// Drop-in replacement for `SwiftSyntaxMacrosTestSupport.assertMacroExpansion`
/// that records failures as Swift Testing issues.
func assertMacroExpansion(
    _ originalSource: String,
    expandedSource expectedExpandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    macros: [String: any Macro.Type],
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
        originalSource,
        expandedSource: expectedExpandedSource,
        diagnostics: diagnostics,
        macroSpecs: macros.mapValues { MacroSpec(type: $0) },
        testModuleName: testModuleName,
        testFileName: testFileName,
        indentationWidth: indentationWidth,
        failureHandler: { failure in
            Issue.record(
                Comment(rawValue: failure.message),
                sourceLocation: SourceLocation(
                    fileID: failure.location.fileID,
                    filePath: failure.location.filePath,
                    line: failure.location.line,
                    column: failure.location.column
                )
            )
        },
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
    )
}
