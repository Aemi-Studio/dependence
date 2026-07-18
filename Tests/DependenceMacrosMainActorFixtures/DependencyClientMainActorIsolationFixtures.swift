//
//  DependencyClientMainActorIsolationFixtures.swift
//  DependenceMacrosMainActorFixtures
//
//  Compile-time regression fixtures for the interaction between
//  `@DependencyClient` and modules built with
//  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
//
//  The Xcode 26 default-isolation knob makes every declaration in a module
//  implicitly `@MainActor`. Before the fix, `@DependencyClient` would
//  synthesize a `@MainActor`-isolated `init` and `static var
//  unimplemented`, which poisoned any `nonisolated static let preview =
//  Self(...)` declaration:
//
//      error: nonisolated initialization of 'preview' cannot reference
//             main actor-isolated initializer 'init(...)'
//
//  The fix marks both synthesized members `nonisolated`. This target pins
//  that contract: if the synthesis regresses, the fixtures below stop
//  compiling. **The gate is the build** — this is a plain library target
//  (not a test target), because linking an `.xctest` bundle that
//  transitively depends on the macro plugin trips a SwiftBuild-backend
//  toolchain bug (the plugin's objects are pulled into the test-bundle
//  link without the SwiftSyntax libraries). A compile-only target avoids
//  the bundle link entirely while keeping the regression coverage: CI
//  builds it on every run via `swift build`.
//

import Dependence
import DependenceMacros
import Foundation

// MARK: - @DependencyClient fixture

/// Witness in a `defaultIsolation(MainActor.self)` module.
///
/// Every member of this struct — including the synthesized `init` and
/// `unimplemented` — would inherit MainActor isolation if `@DependencyClient`
/// did not stamp `nonisolated` explicitly (see Package.swift).
@DependencyClient
struct MainActorWitness: Sendable {
    var ping: @Sendable () -> Void
    var fetch: @Sendable (Int) async throws -> String
}

extension MainActorWitness {
    /// The friction site.
    ///
    /// Calling `Self(...)` from a `nonisolated` context requires the
    /// synthesized init to itself be `nonisolated`.
    nonisolated static let preview = Self(
        ping: {},
        fetch: { _ in "preview" }
    )

    /// Same shape for the synthesized static witness.
    ///
    /// Referencing `unimplemented` from a `nonisolated` declaration requires
    /// the accessor to be `nonisolated` too. Never evaluated at runtime —
    /// the reference existing is the assertion.
    nonisolated static let unimplementedProbe: MainActorWitness = .unimplemented
}
