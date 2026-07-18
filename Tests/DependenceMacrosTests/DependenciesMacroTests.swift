//
//  DependenciesMacroTests.swift
//  DependenceMacrosTests
//

import DependenceMacrosPlugin
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Dependencies expansion")
struct DependenciesMacroTests {
    let macros: [String: any Macro.Type] = [
        "Dependencies": DependenciesMacro.self
    ]

    @Test("Stamps module-qualified @Observation.ObservationIgnored @Dependency for each key path")
    func multipleKeyPaths() {
        assertMacroExpansion(
            """
            @Dependencies(\\.authClient, \\.feedClient)
            final class HomeViewModel {
            }
            """,
            expandedSource: """
                final class HomeViewModel {

                    @Observation.ObservationIgnored
                    @Dependence.Dependency(\\.authClient) private var authClient

                    @Observation.ObservationIgnored
                    @Dependence.Dependency(\\.feedClient) private var feedClient
                }
                """,
            macros: macros
        )
    }

    @Test("Diagnoses an empty argument list")
    func emptyArgumentList() {
        assertMacroExpansion(
            """
            @Dependencies()
            final class Empty {
            }
            """,
            expandedSource: """
                final class Empty {
                }
                """,
            diagnostics: [
                .init(
                    message:
                        "@Dependencies requires one or more key path literals, e.g. `@Dependencies(\\.apiClient)`.",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    @Test("Skips duplicate key paths silently")
    func duplicateKeyPaths() {
        assertMacroExpansion(
            """
            @Dependencies(\\.apiClient, \\.apiClient)
            final class Model {
            }
            """,
            expandedSource: """
                final class Model {

                    @Observation.ObservationIgnored
                    @Dependence.Dependency(\\.apiClient) private var apiClient
                }
                """,
            macros: macros
        )
    }
}
