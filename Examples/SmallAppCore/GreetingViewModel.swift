//
//  GreetingViewModel.swift
//  ExampleSmallAppCore
//

import Dependence
import DependenceMacros
import Foundation
import Observation

/// Trivial view-model that pulls a greeting through `APIClient`.
///
/// `@Dependency(\.apiClient)` re-resolves on each access from the active
/// `DependencyValues`, so unit tests / previews can swap the witness.
@MainActor
@Observable
@Dependencies(\.apiClient)
public final class GreetingViewModel {
    public private(set) var greeting: String = "…"
    public private(set) var error: String?

    public init() {}

    public func load() async {
        do {
            greeting = try await apiClient.fetchGreeting()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}
