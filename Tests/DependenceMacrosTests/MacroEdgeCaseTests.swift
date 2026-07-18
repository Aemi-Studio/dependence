//
//  MacroEdgeCaseTests.swift
//  DependenceMacrosTests
//
//  Edge-case diagnostics and synthesis shapes for `@DependencyClient` and
//  `@DependencyEntry` — inputs that used to fail opaquely (errors pointing
//  into the expansion) or be silently dropped.
//

import DependenceMacrosPlugin
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@DependencyClient edge cases")
struct DependencyClientEdgeCaseTests {
    let macros: [String: any Macro.Type] = [
        "DependencyClient": DependencyClientMacro.self
    ]

    @Test("let without an initializer is a clear diagnostic, not an opaque init failure")
    func letWithoutInitializerDiagnoses() {
        assertMacroExpansion(
            """
            @DependencyClient
            struct Client: Sendable {
                let region: String
                var ping: @Sendable () -> Void
            }
            """,
            expandedSource: """
                struct Client: Sendable {
                    let region: String
                    var ping: @Sendable () -> Void

                    nonisolated init(ping: @escaping @Sendable () -> Void = {
                            Dependence.reportIssue("unimplemented: ping")
                        }) {
                        self.ping = ping
                    }

                    nonisolated static var unimplemented: Self {
                        Self()
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@DependencyClient does not support 'let' properties without an initializer: 'region' cannot "
                        + "be assigned by the synthesized memberwise init. Declare it 'var', or give it an inline "
                        + "default value.",
                    line: 3,
                    column: 5
                )
            ],
            macros: macros
        )
    }

    @Test("let with an inline default participates silently (already initialized)")
    func letWithInitializerIsFine() {
        assertMacroExpansion(
            """
            @DependencyClient
            struct Client: Sendable {
                let region = "eu"
                var ping: @Sendable () -> Void
            }
            """,
            expandedSource: """
                struct Client: Sendable {
                    let region = "eu"
                    var ping: @Sendable () -> Void

                    nonisolated init(ping: @escaping @Sendable () -> Void = {
                            Dependence.reportIssue("unimplemented: ping")
                        }) {
                        self.ping = ping
                    }

                    nonisolated static var unimplemented: Self {
                        Self()
                    }
                }
                """,
            macros: macros
        )
    }

    @Test("Multi-binding declarations are a clear diagnostic")
    func multiBindingDiagnoses() {
        assertMacroExpansion(
            """
            @DependencyClient
            struct Client: Sendable {
                var start, stop: @Sendable () -> Void
            }
            """,
            expandedSource: """
                struct Client: Sendable {
                    var start, stop: @Sendable () -> Void

                    nonisolated init() {

                    }

                    nonisolated static var unimplemented: Self {
                        Self()
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@DependencyClient does not support multiple bindings in one declaration (e.g. `var a, b: T`). "
                        + "Declare each property separately so the synthesized memberwise init can name every parameter.",
                    line: 3,
                    column: 5
                )
            ],
            macros: macros
        )
    }

    @Test("Typed-throws member gets a clear diagnostic and becomes a required parameter")
    func typedThrowsDiagnosesAndRequiresArgument() {
        assertMacroExpansion(
            """
            @DependencyClient
            struct Client: Sendable {
                var load: @Sendable () throws(LoadError) -> Void
            }
            """,
            expandedSource: """
                struct Client: Sendable {
                    var load: @Sendable () throws(LoadError) -> Void

                    nonisolated init(load: @escaping @Sendable () throws(LoadError) -> Void) {
                        self.load = load
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "Closure 'load' uses typed throws 'throws(LoadError)'; the synthesized unimplemented default "
                        + "throws 'DependencyError.unimplemented', which cannot convert to 'LoadError'. Typed-throws "
                        + "members need an explicit default: pass 'load:' at every call site, or use untyped 'throws' "
                        + "(or 'throws(DependencyError)') to keep the synthesized default.",
                    line: 3,
                    column: 5
                )
            ],
            macros: macros
        )
    }

    @Test("throws(DependencyError) keeps the synthesized default (the thrown value fits)")
    func dependencyErrorTypedThrowsKeepsDefault() {
        assertMacroExpansion(
            """
            @DependencyClient
            struct Client: Sendable {
                var load: @Sendable () throws(DependencyError) -> Void
            }
            """,
            expandedSource: """
                struct Client: Sendable {
                    var load: @Sendable () throws(DependencyError) -> Void

                    nonisolated init(load: @escaping @Sendable () throws(DependencyError) -> Void = {
                            Dependence.reportIssue("unimplemented: load");
                            throw Dependence.DependencyError.unimplemented("load")
                        }) {
                        self.load = load
                    }

                    nonisolated static var unimplemented: Self {
                        Self()
                    }
                }
                """,
            macros: macros
        )
    }

    @Test("Optional closure members default to nil in the memberwise init")
    func optionalClosureDefaultsToNil() {
        assertMacroExpansion(
            """
            @DependencyClient
            struct Client: Sendable {
                var ping: @Sendable () -> Void
                var onEvent: (@Sendable (Int) -> Void)?
            }
            """,
            expandedSource: """
                struct Client: Sendable {
                    var ping: @Sendable () -> Void
                    var onEvent: (@Sendable (Int) -> Void)?

                    nonisolated init(ping: @escaping @Sendable () -> Void = {
                            Dependence.reportIssue("unimplemented: ping")
                        }, onEvent: (@Sendable (Int) -> Void)? = nil) {
                        self.ping = ping
                        self.onEvent = onEvent
                    }

                    nonisolated static var unimplemented: Self {
                        Self()
                    }
                }
                """,
            macros: macros
        )
    }
}

@Suite("@DependencyEntry edge cases")
struct DependencyEntryEdgeCaseTests {
    let macros: [String: any Macro.Type] = [
        "DependencyEntry": DependencyEntryMacro.self
    ]

    @Test("Interface form with preview:/test: arguments is a clear diagnostic, not a silent drop")
    func interfaceFormWithWitnessesDiagnoses() {
        assertMacroExpansion(
            """
            extension DependencyValues {
                @DependencyEntry(preview: APIClient.preview) var apiClient: APIClient
            }
            """,
            expandedSource: """
                extension DependencyValues {
                    var apiClient: APIClient {
                        get {
                            self[test: APIClientKey.self]
                        }
                        set {
                            self[test: APIClientKey.self] = newValue
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'preview:'/'test:' arguments require an initializer providing the liveValue. The interface "
                        + "form (no initializer) routes through an externally-declared '<Type>Key: TestDependencyKey' "
                        + "— declare 'previewValue'/'testValue' on that key instead.",
                    line: 2,
                    column: 5
                )
            ],
            macros: macros
        )
    }

    @Test("Computed property is a clear diagnostic")
    func computedPropertyDiagnoses() {
        assertMacroExpansion(
            """
            extension DependencyValues {
                @DependencyEntry var apiClient: APIClient { fatalError() }
            }
            """,
            expandedSource: """
                extension DependencyValues {
                    var apiClient: APIClient { fatalError() }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@DependencyEntry cannot be applied to a computed property — the macro generates the accessors "
                        + "itself. Declare a stored-style property (`var apiClient: APIClient = .live`) instead.",
                    line: 2,
                    column: 47
                )
            ],
            macros: macros
        )
    }
}
