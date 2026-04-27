//
//  Diagnostics.swift
//  DependenceMacrosPlugin
//

import SwiftDiagnostics
import SwiftSyntax

enum DependenceDiagnostic: DiagnosticMessage {
    case dependencyEntryRequiresVar
    case dependencyEntryRequiresInitializer
    case dependencyClientRequiresStruct
    case dependenciesRequiresKeyPathArgument
    case dependenciesKeyPathMissingPropertyComponent
    case dependencyClientNonThrowingNonVoidClosure(name: String, returnType: String)

    private var rawValue: String {
        switch self {
        case .dependencyEntryRequiresVar: return "dependencyEntryRequiresVar"
        case .dependencyEntryRequiresInitializer: return "dependencyEntryRequiresInitializer"
        case .dependencyClientRequiresStruct: return "dependencyClientRequiresStruct"
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
            return "@DependencyEntry requires an initializer providing the liveValue, e.g. `var apiClient = APIClient.live`."
        case .dependencyClientRequiresStruct:
            return "@DependencyClient can only be applied to a struct."
        case .dependenciesRequiresKeyPathArgument:
            return "@Dependencies requires one or more key path literals, e.g. `@Dependencies(\\.apiClient)`."
        case .dependenciesKeyPathMissingPropertyComponent:
            return "@Dependencies key paths must reference a single named property of `DependencyValues`, e.g. `\\.apiClient`."
        case let .dependencyClientNonThrowingNonVoidClosure(name, returnType):
            return "Closure '\(name)' returns '\(returnType)' and is not 'throws'; the synthesized 'unimplemented' default will trap at runtime when invoked. Mark it 'throws' to surface unimplemented uses as a recoverable test failure instead."
        }
    }
}
