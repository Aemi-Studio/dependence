//
//  DependencyEntryMainActorIsolationFixtures.swift
//  DependenceMacrosMainActorFixtures
//
//  Compile-time regression fixtures for `@DependencyEntry` in a module
//  built with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
//
//  The generated `__Key_<name>` enum is `nonisolated` and its
//  `liveValue`/`previewValue`/`testValue` witnesses evaluate the user's
//  expressions from a nonisolated context (`DependencyKey` inherits
//  `Sendable`, so the conformance cannot be actor-isolated). That imposes
//  two documented requirements on MainActor-default modules, both pinned
//  here — if either regresses, this target stops compiling:
//
//  1. Witness statics referenced by the default / `preview:` / `test:`
//     expressions must be `nonisolated`. (An implicitly `@MainActor`
//     `static let live` fails inside the expansion with "main
//     actor-isolated static property 'live' can not be referenced from a
//     nonisolated context" — the macro cannot see the witness's isolation,
//     so this is a documentation contract, not a macro diagnostic.)
//  2. Entries that must be readable from nonisolated code are spelled
//     `@DependencyEntry nonisolated var …` — otherwise the accessor is
//     implicitly `@MainActor` and `@Dependency(\.…)` cannot form the key
//     path outside the MainActor.
//

import Dependence
import DependenceMacros
import Foundation

// MARK: - Witness

struct EntryProbeClient: Sendable {
    var value: Int
}

extension EntryProbeClient {
    /// Requirement 1: `nonisolated` keeps these referable from the
    /// generated nonisolated witnesses despite the module's MainActor
    /// default isolation.
    nonisolated static let live = EntryProbeClient(value: 1)
    nonisolated static let previewWitness = EntryProbeClient(value: 2)
    nonisolated static let testWitness = EntryProbeClient(value: 3)
}

// MARK: - Entries

extension DependencyValues {
    /// Bare form with an explicit type annotation.
    @DependencyEntry var mainActorModuleEntry: EntryProbeClient = .live

    /// Labeled form: `preview:`/`test:` expressions are stamped into the
    /// same nonisolated conformance, so they need nonisolated witnesses
    /// exactly like the default expression does.
    @DependencyEntry(preview: EntryProbeClient.previewWitness, test: EntryProbeClient.testWitness)
    var mainActorModuleEntryWithWitnesses: EntryProbeClient = .live

    // NOTE deliberately absent: the *inferred* form
    // (`@DependencyEntry var entry = EntryProbeClient.live`, no type
    // annotation) does not compile in a MainActor-default module — the
    // compiler fails to infer the key's `Value` associated type from the
    // stored `liveValue` under default isolation (verified against both the
    // isolated and `nonisolated` enum shapes; it is a compiler behavior,
    // not a macro one). MainActor-default modules must use the explicit
    // type annotation, as documented on `@DependencyEntry`.

    /// Requirement 2: `nonisolated` on the entry property keeps the
    /// accessor callable — and the key path formable — from nonisolated
    /// contexts.
    @DependencyEntry nonisolated var nonisolatedEntry: EntryProbeClient = .live
}

// MARK: - Nonisolated read

/// Pins requirement 2 from the consuming side.
///
/// Forms `\DependencyValues.nonisolatedEntry` and reads through
/// `@Dependency` from a nonisolated function. Never called at runtime —
/// compiling is the assertion.
nonisolated func readEntryFromNonisolatedContext() -> Int {
    @Dependency(\.nonisolatedEntry) var client
    return client.value
}
