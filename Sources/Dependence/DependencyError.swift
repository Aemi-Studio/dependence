//
//  DependencyError.swift
//  Dependence
//

import Foundation

/// Errors thrown by the dependency system at runtime.
///
/// Core resolution paths report issues through ``IssueReporter`` (which routes
/// to Swift Testing, XCTest, or runtime warnings depending on context) and
/// surface recoverable failures here so callers can `catch` them
/// deterministically when needed.
///
/// A synthesized `@DependencyClient` default for a non-throwing, non-`Void`
/// closure still has to trap after reporting because there is no value it can
/// return. Prefer `throws` for endpoints whose unimplemented path should be
/// recoverable in tests.
public enum DependencyError: Error, Sendable {
    /// A `DependencyKey`'s `liveValue` was accessed but no value is registered
    /// in the current context. Carries a human-readable label.
    case missingLiveValue(String)

    /// A cycle was detected during resolution.
    /// The path lists the keys visited from the cycle's entry point.
    case cycle([String])

    /// A test-context call hit an `unimplemented` sentinel.
    case unimplemented(String)
}

extension DependencyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingLiveValue(let label):
            return "Dependence: no live value registered for \(label)."
        case .cycle(let path):
            return "Dependence: dependency cycle detected — \(path.joined(separator: " → "))."
        case .unimplemented(let label):
            return "Dependence: \(label) is unimplemented."
        }
    }
}
