//
//  Diagnostics.swift
//  DependenceMacrosPlugin
//

import SwiftDiagnostics
import SwiftSyntax

enum DependenceDiagnostic: DiagnosticMessage {
    case dependencyEntryRequiresVar
    case dependencyEntryRequiresInitializer
    case dependencyEntryComputedPropertyUnsupported
    case dependencyEntryInterfaceFormDropsWitnesses
    case dependencyClientRequiresStruct
    case dependencyClientLetRequiresInitializer(name: String)
    case dependencyClientMultipleBindings
    case dependencyClientTypedThrowsNeedsDefault(name: String, thrownType: String)
    case dependenciesRequiresKeyPathArgument
    case dependenciesKeyPathMissingPropertyComponent
    case dependencyClientNonThrowingNonVoidClosure(name: String, returnType: String)

    private var rawValue: String {
        switch self {
            case .dependencyEntryRequiresVar: return "dependencyEntryRequiresVar"
            case .dependencyEntryRequiresInitializer: return "dependencyEntryRequiresInitializer"
            case .dependencyEntryComputedPropertyUnsupported: return "dependencyEntryComputedPropertyUnsupported"
            case .dependencyEntryInterfaceFormDropsWitnesses: return "dependencyEntryInterfaceFormDropsWitnesses"
            case .dependencyClientRequiresStruct: return "dependencyClientRequiresStruct"
            case .dependencyClientLetRequiresInitializer: return "dependencyClientLetRequiresInitializer"
            case .dependencyClientMultipleBindings: return "dependencyClientMultipleBindings"
            case .dependencyClientTypedThrowsNeedsDefault: return "dependencyClientTypedThrowsNeedsDefault"
            case .dependenciesRequiresKeyPathArgument: return "dependenciesRequiresKeyPathArgument"
            case .dependenciesKeyPathMissingPropertyComponent: return "dependenciesKeyPathMissingPropertyComponent"
            case .dependencyClientNonThrowingNonVoidClosure: return "dependencyClientNonThrowingNonVoidClosure"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "DependenceMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        switch self {
            case .dependencyClientNonThrowingNonVoidClosure:
                return .warning
            default:
                return .error
        }
    }

    var message: String {
        switch self {
            case .dependencyEntryRequiresVar:
                return "@DependencyEntry can only be applied to a 'var' property."
            case .dependencyEntryRequiresInitializer:
                return
                    "@DependencyEntry requires an initializer providing the liveValue, e.g. `var apiClient = APIClient.live`."
            case .dependencyEntryComputedPropertyUnsupported:
                return
                    "@DependencyEntry cannot be applied to a computed property — the macro generates the accessors itself. "
                    + "Declare a stored-style property (`var apiClient: APIClient = .live`) instead."
            case .dependencyEntryInterfaceFormDropsWitnesses:
                return
                    "'preview:'/'test:' arguments require an initializer providing the liveValue. The interface form "
                    + "(no initializer) routes through an externally-declared '<Type>Key: TestDependencyKey' — declare "
                    + "'previewValue'/'testValue' on that key instead."
            case .dependencyClientRequiresStruct:
                return "@DependencyClient can only be applied to a struct."
            case .dependencyClientLetRequiresInitializer(let name):
                return
                    "@DependencyClient does not support 'let' properties without an initializer: '\(name)' cannot be "
                    + "assigned by the synthesized memberwise init. Declare it 'var', or give it an inline default value."
            case .dependencyClientMultipleBindings:
                return
                    "@DependencyClient does not support multiple bindings in one declaration (e.g. `var a, b: T`). "
                    + "Declare each property separately so the synthesized memberwise init can name every parameter."
            case .dependencyClientTypedThrowsNeedsDefault(let name, let thrownType):
                return
                    "Closure '\(name)' uses typed throws 'throws(\(thrownType))'; the synthesized unimplemented default "
                    + "throws 'DependencyError.unimplemented', which cannot convert to '\(thrownType)'. Typed-throws "
                    + "members need an explicit default: pass '\(name):' at every call site, or use untyped 'throws' "
                    + "(or 'throws(DependencyError)') to keep the synthesized default."
            case .dependenciesRequiresKeyPathArgument:
                return "@Dependencies requires one or more key path literals, e.g. `@Dependencies(\\.apiClient)`."
            case .dependenciesKeyPathMissingPropertyComponent:
                return
                    "@Dependencies key paths must reference a single named property of `DependencyValues`, e.g. `\\.apiClient`."
            case .dependencyClientNonThrowingNonVoidClosure(let name, let returnType):
                return
                    "Closure '\(name)' returns '\(returnType)' and is not 'throws'; the synthesized 'unimplemented' "
                    + "default will trap at runtime when invoked. Mark it 'throws' to surface unimplemented uses as a "
                    + "recoverable test failure instead."
        }
    }
}
