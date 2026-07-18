//
//  Macros.swift
//  DependenceMacros
//
//  Public macro declarations. Implementations live in
//  `DependenceMacrosPlugin`. The plugin is not a runtime dependency; it is
//  invoked by the compiler during build only.
//

@_exported import Dependence

/// Declare a dependency entry on `DependencyValues`.
///
/// ```swift
/// extension DependencyValues {
///     @DependencyEntry public var apiClient = APIClient.live
/// }
/// ```
///
/// Expands into a get/set pair routed through a generated `DependencyKey` —
/// no manual key boilerplate required. Mirrors SwiftUI's `@Entry`.
///
/// The default expression produces the `liveValue` for the key. To wire
/// `previewValue` / `testValue` directly into the conformance — so that
/// `#Preview` blocks and `swift test` runs auto-resolve to those witnesses
/// without any modifier — pass them through the labeled forms:
///
/// ```swift
/// @DependencyEntry(preview: X.preview)                       public var x: X = .live
/// @DependencyEntry(test: Y.unimplemented)                    public var y: Y = .live
/// @DependencyEntry(preview: Z.preview, test: Z.unimplemented) public var z: Z = .live
/// ```
///
/// Omitted witnesses fall through to `liveValue` via `DependencyKey`'s
/// protocol default — the same behavior as the bare form.
///
/// The argument types are deliberately `Any`: macros can't read the
/// surrounding property's type at attribute-resolution time, so we'd lose
/// `.preview` shorthand to inference errors. The expansion stamps the
/// expression verbatim into the generated conformance — a typo is caught
/// at compile time inside the expansion, not at the macro call site.
///
/// ## Modules built with default isolation `MainActor`
///
/// Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (the Xcode 26 app
/// default), two declarations need explicit `nonisolated`:
///
/// 1. **The witness statics** referenced by the default expression and by
///    `preview:` / `test:` arguments. The generated key's `liveValue` /
///    `previewValue` / `testValue` are nonisolated protocol witnesses
///    (`DependencyKey` inherits `Sendable`, so the conformance cannot be
///    actor-isolated), and they evaluate your expression verbatim. An
///    implicitly `@MainActor` `static let live` therefore fails with
///    "main actor-isolated static property 'live' can not be referenced
///    from a nonisolated context" pointing into the macro expansion. The
///    macro cannot see the witness's isolation to diagnose this earlier —
///    write `nonisolated static let live = …` on the witness type.
/// 2. **The entry property itself**, if it must be readable from
///    nonisolated code: an implicitly `@MainActor` accessor makes
///    `@Dependency(\.entry)` fail with "cannot form key path to main
///    actor-isolated property" outside the MainActor. Spell it
///    `@DependencyEntry nonisolated var entry: T = .live`.
///
/// Additionally, write the **explicit type annotation** in such modules
/// (`var entry: T = .live`, not `var entry = T.live`): the inferred form
/// relies on associated-type inference from the generated stored
/// `liveValue`, which the compiler does not perform under default
/// isolation `MainActor`.
///
/// The `DependenceMacrosMainActorFixtures` target pins these requirements
/// as compile-time regressions.
@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro DependencyEntry() =
    #externalMacro(
        module: "DependenceMacrosPlugin",
        type: "DependencyEntryMacro"
    )

@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro DependencyEntry(preview: Any) =
    #externalMacro(
        module: "DependenceMacrosPlugin",
        type: "DependencyEntryMacro"
    )

@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro DependencyEntry(test: Any) =
    #externalMacro(
        module: "DependenceMacrosPlugin",
        type: "DependencyEntryMacro"
    )

@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro DependencyEntry(preview: Any, test: Any) =
    #externalMacro(
        module: "DependenceMacrosPlugin",
        type: "DependencyEntryMacro"
    )

/// Generate a memberwise initializer that supplies an `unimplemented` default
/// for every closure-typed property of a witness struct.
///
/// ```swift
/// @DependencyClient
/// public struct APIClient: Sendable {
///     public var fetch: @Sendable (URL) async throws -> Data
///     public var upload: @Sendable (Data) async throws -> Void
/// }
/// ```
///
/// Synthesizes:
/// - `public init(fetch:upload:)` with each parameter defaulting to a closure
///   that reports an issue and throws `DependencyError.unimplemented`.
/// - A `static let unimplemented` value with all defaults.
///
/// Pure properties (non-closure) are required parameters in the generated
/// init — they always need a real value.
@attached(member, names: named(init), named(unimplemented))
public macro DependencyClient() =
    #externalMacro(
        module: "DependenceMacrosPlugin",
        type: "DependencyClientMacro"
    )

/// Synthesize `@ObservationIgnored @Dependency(\.<name>) private var <name>`
/// stored properties from a list of dependency key paths.
///
/// ```swift
/// @MainActor
/// @Observable
/// @Dependencies(\.authClient, \.feedClient, \.profileClient)
/// final class HomeViewModel { /* ... */ }
/// ```
///
/// Each key path's trailing identifier becomes the property name. Property
/// types are inferred from `@Dependency`'s `wrappedValue`, which is generic
/// over the key path's `Value`. The macro never reads a type from
/// `DependencyValues`; the compiler resolves it during the second pass.
///
/// `@ObservationIgnored` is always stamped because `@Dependency`'s storage
/// must not participate in `Observation` tracking — `@Dependency` is a
/// resolution port, not view-model state.
@attached(member, names: arbitrary)
public macro Dependencies(_ keyPaths: PartialKeyPath<Dependence.DependencyValues>...) =
    #externalMacro(
        module: "DependenceMacrosPlugin",
        type: "DependenciesMacro"
    )
