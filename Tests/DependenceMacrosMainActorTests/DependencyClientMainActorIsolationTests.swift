//
//  DependencyClientMainActorIsolationTests.swift
//  DependenceTests
//
//  Compile-time regression for the interaction between `@DependencyClient`
//  and modules built with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
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
//  The fix marks both synthesized members `nonisolated`. This file pins
//  that contract: if the synthesis regresses, the code below stops
//  compiling. The runtime assertions are intentionally trivial — the real
//  test is the build.
//

import Dependence
import DependenceMacros
import Foundation
import Testing

// MARK: - Fixture

/// Witness mounted explicitly on `@MainActor` to mimic a module that sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Every member of this
/// struct — including the synthesized `init` and `unimplemented` — would
/// inherit MainActor isolation if `@DependencyClient` did not stamp
/// `nonisolated` explicitly.
@MainActor
@DependencyClient
struct MainActorWitness: Sendable {
    var ping: @Sendable () -> Void
    var fetch: @Sendable (Int) async throws -> String
}

extension MainActorWitness {
    /// The friction site. Calling `Self(...)` from a `nonisolated` context
    /// requires the synthesized init to itself be `nonisolated`.
    nonisolated static let preview = Self(
        ping: { },
        fetch: { _ in "preview" }
    )
}

// MARK: - Tests

@Suite("@DependencyClient under @MainActor")
struct DependencyClientMainActorIsolationTests {

    @Test("nonisolated static let preview compiles against a @MainActor witness")
    func previewIsConstructibleFromNonisolated() {
        // The interesting check is that this file compiled at all. The
        // runtime assertion is a sanity check on the preview closures.
        let witness = MainActorWitness.preview
        witness.ping()
    }

    @Test("nonisolated static var unimplemented is reachable from a nonisolated context")
    func unimplementedIsReachableFromNonisolated() async {
        // Same shape: the call site is nonisolated; the synthesized
        // `unimplemented` accessor must therefore be nonisolated too.
        let witness = MainActorWitness.unimplemented
        // Don't invoke `ping` or `fetch` — the unimplemented closures call
        // `reportIssue`, which would fail this very test. The point is
        // that the value can be *constructed* from a nonisolated context.
        _ = witness
    }
}
