//
//  DependencyEntryMacroTests.swift
//  DependenceMacrosTests
//

import DependenceMacrosPlugin
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@Suite("@DependencyEntry expansion")
struct DependencyEntryMacroTests {
    let macros: [String: any Macro.Type] = [
        "DependencyEntry": DependencyEntryMacro.self,
    ]

    @Test("Generates a key with explicit type and routes get/set through it")
    func explicitType() {
        assertMacroExpansion(
            """
            extension DependencyValues {
                @DependencyEntry public var apiClient: APIClient = .live
            }
            """,
            expandedSource: """
            extension DependencyValues {
                public var apiClient: APIClient {
                    get { self[__Key_apiClient.self] }
                    set { self[__Key_apiClient.self] = newValue }
                }

                fileprivate enum __Key_apiClient: Dependence.DependencyKey {
                    typealias Value = APIClient
                    static var liveValue: APIClient {
                        .live
                    }
                }
            }
            """,
            macros: macros
        )
    }

    @Test("Stamps previewValue into the conformance when preview: is supplied")
    func previewArgument() {
        assertMacroExpansion(
            """
            extension DependencyValues {
                @DependencyEntry(preview: APIClient.preview) public var apiClient: APIClient = .live
            }
            """,
            expandedSource: """
            extension DependencyValues {
                public var apiClient: APIClient {
                    get { self[__Key_apiClient.self] }
                    set { self[__Key_apiClient.self] = newValue }
                }

                fileprivate enum __Key_apiClient: Dependence.DependencyKey {
                    typealias Value = APIClient
                    static var liveValue: APIClient {
                        .live
                    }
                    static var previewValue: APIClient {
                        APIClient.preview
                    }
                }
            }
            """,
            macros: macros
        )
    }

    @Test("Stamps testValue into the conformance when test: is supplied")
    func testArgument() {
        assertMacroExpansion(
            """
            extension DependencyValues {
                @DependencyEntry(test: APIClient.unimplemented) public var apiClient: APIClient = .live
            }
            """,
            expandedSource: """
            extension DependencyValues {
                public var apiClient: APIClient {
                    get { self[__Key_apiClient.self] }
                    set { self[__Key_apiClient.self] = newValue }
                }

                fileprivate enum __Key_apiClient: Dependence.DependencyKey {
                    typealias Value = APIClient
                    static var liveValue: APIClient {
                        .live
                    }
                    static var testValue: APIClient {
                        APIClient.unimplemented
                    }
                }
            }
            """,
            macros: macros
        )
    }

    @Test("Stamps both witnesses when preview: and test: are supplied")
    func previewAndTestArguments() {
        assertMacroExpansion(
            """
            extension DependencyValues {
                @DependencyEntry(preview: APIClient.preview, test: APIClient.unimplemented)
                public var apiClient: APIClient = .live
            }
            """,
            expandedSource: """
            extension DependencyValues {
                public var apiClient: APIClient {
                    get { self[__Key_apiClient.self] }
                    set { self[__Key_apiClient.self] = newValue }
                }

                fileprivate enum __Key_apiClient: Dependence.DependencyKey {
                    typealias Value = APIClient
                    static var liveValue: APIClient {
                        .live
                    }
                    static var previewValue: APIClient {
                        APIClient.preview
                    }
                    static var testValue: APIClient {
                        APIClient.unimplemented
                    }
                }
            }
            """,
            macros: macros
        )
    }
}
