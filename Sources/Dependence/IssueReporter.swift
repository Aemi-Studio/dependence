//
//  IssueReporter.swift
//  Dependence
//
//  Native replacement for `pointfreeco/swift-issue-reporting`. Detects the
//  current execution context (Swift Testing, XCTest, SwiftUI Preview, plain
//  runtime) and routes the issue to the appropriate sink.
//
//  IMPORTANT: this file deliberately does **not** `import Testing`. On modern
//  Apple SDKs `Testing` can be importable from non-test targets, so even a
//  `#if canImport(Testing)` guard would force the `Dependence` library to link
//  `Testing.framework` at build time. That framework is only embedded in test
//  bundles, not in app products, so an executable depending on `Dependence`
//  could fail at launch with
//  `dyld: Library not loaded: @rpath/Testing.framework/Testing`.
//
//  Swift Testing routing is provided by `DependenceTesting`, which is allowed
//  to link `Testing.framework` because it only ships in test targets. It
//  registers a handler through `IssueReporter.register(_:)` below.
//

import Foundation
import Synchronization
#if canImport(ObjectiveC)
import ObjectiveC
#endif
#if canImport(MachO)
import MachO
#endif

/// Reports an "issue" — a non-fatal failure that should surface as a test
/// failure in tests, a runtime warning in development, and an `os_log` warning
/// in production.
///
/// This is used by `unimplemented` sentinels, cycle detection, duplicate
/// registration, and other recoverable misconfigurations. It never traps.
@inlinable
public func reportIssue(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    let text = message()

    // Give externally-registered handlers (e.g. Swift Testing routing
    // installed by `DependenceTesting`) the first chance to consume the issue.
    for handler in IssueReporter._handlers() {
        if handler(
            text,
            String(describing: fileID),
            String(describing: filePath),
            Int(line),
            Int(column)
        ) {
            return
        }
    }

    switch IssueContext.current {
    case .swiftTesting:
        // Swift Testing is loaded but no handler claimed the issue — most
        // likely because `DependenceTesting` wasn't linked. Fall back to a
        // runtime warning so the message is still visible.
        RuntimeWarning.emit(text, file: filePath, line: line)
    case .xctest:
        IssueContext.routeToXCTest(message: text, file: filePath, line: line)
    case .preview, .runtime:
        RuntimeWarning.emit(text, file: filePath, line: line)
    }
}

// MARK: - Public registration API

/// Namespace for extending `reportIssue(_:)`'s routing behaviour.
///
/// `Dependence` is a Foundation-only library and must not link
/// `Testing.framework`. Code that *can* link it (notably `DependenceTesting`)
/// installs a handler here so issues raised during a Swift Testing run surface
/// as proper `Issue.record` failures instead of `os_log` warnings.
public enum IssueReporter {
    /// Returns `true` if the handler consumed the issue.
    ///
    /// Returning `false` lets `reportIssue` fall through to the next handler
    /// or to the built-in fallbacks (XCTest routing, runtime warning).
    public typealias Handler = @Sendable (
        _ message: String,
        _ fileID: String,
        _ filePath: String,
        _ line: Int,
        _ column: Int
    ) -> Bool

    /// Register a handler invoked by `reportIssue(_:)` before the built-in
    /// fallbacks. Handlers are tried in registration order.
    public static func register(_ handler: @escaping Handler) {
        _storage.withLock { state in
            state.handlers.append(handler)
            // Publish a fresh immutable snapshot. Readers grab it through
            // `_handlers()` without copying the underlying array on every
            // `reportIssue` call.
            state.snapshot = state.handlers
        }
    }

    /// Snapshot of currently-registered handlers. Exposed `@usableFromInline`
    /// so the inlined `reportIssue` body can iterate them.
    ///
    /// The returned array shares storage with the published snapshot — Swift
    /// arrays are value types with COW semantics, so a read on the hot path
    /// is one locked pointer fetch with no allocation.
    @usableFromInline
    static func _handlers() -> [Handler] {
        _storage.withLock { $0.snapshot }
    }

    @usableFromInline
    struct State: Sendable {
        @usableFromInline
        var handlers: [Handler] = []

        /// Cached read-only snapshot republished on every `register`. Keeps
        /// `reportIssue` reads cheap when handler registration is rare
        /// (the typical pattern: one bootstrap call per process).
        @usableFromInline
        var snapshot: [Handler] = []

        @usableFromInline
        init() {}
    }

    /// Process-wide handler state. Same locking pattern as
    /// `DependencyValues.cache`.
    @usableFromInline
    static let _storage: Mutex<State> = Mutex(State())
}

// MARK: - Context detection

@usableFromInline
package enum IssueContext: Sendable, Hashable {
    case swiftTesting
    case xctest
    case preview
    case runtime

    /// Probe the current process for a test or preview context.
    ///
    /// The probes are ordered by **specificity**, not by detection cost:
    ///
    /// 1. `XCODE_RUNNING_FOR_PREVIEWS == "1"` — SwiftUI preview sandbox.
    ///    Checked first because Xcode's preview shim *also* loads
    ///    `XCTest.framework` into the preview process for diagnostic
    ///    plumbing. If we probed for `XCTestCase` first, every preview
    ///    would be misclassified as `.xctest` and resolve to `testValue`
    ///    (which usually falls through to `liveValue`), defeating
    ///    `@DependencyEntry(preview: …)` registrations entirely.
    /// 2. `Testing.framework` is loaded into the address space — Swift
    ///    Testing.
    /// 3. `objc_lookUpClass("XCTestCase")` — XCTest is linked into the
    ///    process. Tests in the same process as a preview shim are
    ///    impossible in practice, so this only fires for genuine XCTest
    ///    runs.
    /// 4. otherwise, plain runtime.
    @usableFromInline
    package static var current: IssueContext {
        #if canImport(ObjectiveC)
        let isXCTestLoaded = objc_lookUpClass("XCTestCase") != nil
        #else
        let isXCTestLoaded = false
        #endif
        return resolve(
            environment: ProcessInfo.processInfo.environment,
            isSwiftTestingLoaded: _isSwiftTestingLoaded,
            isXCTestLoaded: isXCTestLoaded
        )
    }

    /// Pure resolver used by tests so they do not need to mutate process-wide
    /// environment variables while Swift Testing is running suites in parallel.
    @usableFromInline
    package static func resolve(
        environment: [String: String],
        isSwiftTestingLoaded: Bool,
        isXCTestLoaded: Bool
    ) -> IssueContext {
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .preview
        }
        if isSwiftTestingLoaded { return .swiftTesting }
        if isXCTestLoaded { return .xctest }
        return .runtime
    }

    /// Route a message to XCTest's output when present.
    ///
    /// Dynamic XCTest invocation through ObjC runtime selectors was tried
    /// but proved fragile under Swift 6 / Xcode 16+ and is effectively
    /// obsolete now that Swift Testing is the recommended path. We emit a
    /// `[XCTest]`-prefixed runtime warning instead — Xcode surfaces it
    /// alongside the XCTest run output, which is enough to flag the
    /// underlying issue without re-implementing the framework's dispatch.
    @usableFromInline
    package static func routeToXCTest(message: String, file: StaticString, line: UInt) {
        RuntimeWarning.emit("[XCTest] \(message)", file: file, line: line)
    }
}

// MARK: - Swift Testing detection (dyld scan)

/// `true` if `Testing.framework` is currently loaded into this process.
///
/// We scan the dyld image list rather than `import Testing` so the
/// `Dependence` library does not link the framework at build time. The result
/// is computed once per process (the test bundle either loads Testing at
/// startup or never).
@usableFromInline
let _isSwiftTestingLoaded: Bool = {
    #if canImport(MachO)
    let count = _dyld_image_count()
    for i in 0..<count {
        guard let cName = _dyld_get_image_name(i) else { continue }
        let name = String(cString: cName)
        // Matches both
        //   .../Testing.framework/Testing
        //   .../Testing.framework/Versions/A/Testing
        // and the simulator runtime's PackageFrameworks variant.
        if name.contains("/Testing.framework/") {
            return true
        }
    }
    return false
    #else
    return false
    #endif
}()
