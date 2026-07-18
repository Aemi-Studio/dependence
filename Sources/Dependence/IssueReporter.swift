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

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
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

/// Namespace for extending the routing behaviour of `reportIssue(_:)`.
///
/// ## Linking constraints
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
    public typealias Handler =
        @Sendable (
            _ message: String,
            _ fileID: String,
            _ filePath: String,
            _ line: Int,
            _ column: Int
        ) -> Bool

    /// Register a handler invoked by `reportIssue(_:)` before the built-in
    /// fallbacks.
    ///
    /// Handlers are tried in registration order.
    public static func register(_ handler: @escaping Handler) {
        _storage.withLock { state in
            state.handlers.append(handler)
            // Publish a fresh immutable snapshot. Readers grab it through
            // `_handlers()` without copying the underlying array on every
            // `reportIssue` call.
            state.snapshot = state.handlers
        }
    }

    /// Snapshot of currently-registered handlers.
    ///
    /// Exposed `@usableFromInline` so the inlined `reportIssue` body can
    /// iterate them.
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

        /// Cached read-only snapshot republished on every `register`.
        ///
        /// Keeps `reportIssue` reads cheap when handler registration is rare
        /// (the typical pattern: one bootstrap call per process).
        @usableFromInline
        var snapshot: [Handler] = []

        @usableFromInline
        init() {}
    }

    /// Process-wide handler state.
    ///
    /// Same locking pattern as `DependencyValues.cache`.
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
    ///    plumbing. If we probed for XCTest first, every preview would be
    ///    misclassified as `.xctest` and resolve to `testValue` (which
    ///    usually falls through to `liveValue`), defeating
    ///    `@DependencyEntry(preview: …)` registrations entirely.
    /// 2. `Testing.framework` is loaded into the address space — Swift
    ///    Testing.
    /// 3. `XCTest.framework` (or its Swift-support dylib) is loaded — an
    ///    XCTest run. Tests in the same process as a preview shim are
    ///    impossible in practice, so this only fires for genuine XCTest
    ///    runs.
    /// 4. otherwise, plain runtime.
    ///
    /// This sits on **every** resolution's path (including cache hits), so
    /// it must be cheap: the preview flag is one `getenv` computed once per
    /// process, and the two framework probes are relaxed atomic loads kept
    /// up to date by a dyld add-image observer — no environment-dictionary
    /// bridging, no ObjC runtime lookups.
    @usableFromInline
    package static var current: IssueContext {
        // Lazily installs the dyld observer on first use; `swift_once` makes
        // every later touch a single atomic check.
        _ = TestFrameworkPresence.installObserver
        return resolve(
            isPreview: _isPreviewEnvironment,
            isSwiftTestingLoaded: TestFrameworkPresence.swiftTesting.load(ordering: .relaxed),
            isXCTestLoaded: TestFrameworkPresence.xctest.load(ordering: .relaxed)
        )
    }

    /// Single source of truth for the probe precedence. `current` and the
    /// environment-dictionary form below both funnel through this.
    @usableFromInline
    package static func resolve(
        isPreview: Bool,
        isSwiftTestingLoaded: Bool,
        isXCTestLoaded: Bool
    ) -> IssueContext {
        if isPreview { return .preview }
        if isSwiftTestingLoaded { return .swiftTesting }
        if isXCTestLoaded { return .xctest }
        return .runtime
    }

    /// Pure resolver used by tests so they do not need to mutate process-wide
    /// environment variables while Swift Testing is running suites in parallel.
    @usableFromInline
    package static func resolve(
        environment: [String: String],
        isSwiftTestingLoaded: Bool,
        isXCTestLoaded: Bool
    ) -> IssueContext {
        resolve(
            isPreview: environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1",
            isSwiftTestingLoaded: isSwiftTestingLoaded,
            isXCTestLoaded: isXCTestLoaded
        )
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

// MARK: - Context-detection state (preview flag + dyld observer)

/// `true` if this process is Xcode's SwiftUI preview shim.
///
/// Computed once per process through C `getenv` — no
/// `ProcessInfo.environment` bridging (which rebuilds the entire
/// environment dictionary on every access). Xcode sets the variable before
/// the preview process launches, so a one-shot read is exact.
let _isPreviewEnvironment: Bool = {
    guard let raw = getenv("XCODE_RUNNING_FOR_PREVIEWS") else { return false }
    return String(cString: raw) == "1"
}()

/// Tracks whether `Testing.framework` / `XCTest.framework` are loaded into
/// this process, without linking either.
///
/// The flags start from the image list observed when the observer installs
/// and are **upgraded** by a `_dyld_register_func_for_add_image` callback:
/// dyld invokes the callback synchronously for every already-loaded image at
/// registration, then again for each image loaded later. The upgrade path
/// matters — a TEST_HOST app process loads the test bundle (and with it
/// `Testing.framework`) *after* the app, and therefore possibly after the
/// first dependency resolution; a compute-once latch would stick to `false`
/// and misroute every issue for the rest of the run.
///
/// The flags are monotonic (`false` → `true`), so relaxed ordering is
/// sufficient on both sides.
enum TestFrameworkPresence {
    static let swiftTesting = Atomic<Bool>(false)
    static let xctest = Atomic<Bool>(false)

    /// Installs the add-image observer. `static let` gives once semantics;
    /// dyld reports all currently-loaded images synchronously during
    /// registration, so the flags are exact by the time this initializer
    /// returns.
    static let installObserver: Void = {
        #if canImport(MachO)
            _dyld_register_func_for_add_image { header, _ in
                guard let header else { return }
                var info = Dl_info()
                guard dladdr(UnsafeRawPointer(header), &info) != 0, let path = info.dli_fname else {
                    return
                }
                // Matches both
                //   .../Testing.framework/Testing
                //   .../Testing.framework/Versions/A/Testing
                // and the simulator runtime's PackageFrameworks variant.
                if strstr(path, "/Testing.framework/") != nil {
                    TestFrameworkPresence.swiftTesting.store(true, ordering: .relaxed)
                }
                if strstr(path, "/XCTest.framework/") != nil
                    || strstr(path, "libXCTestSwiftSupport") != nil
                {
                    TestFrameworkPresence.xctest.store(true, ordering: .relaxed)
                }
            }
        #endif
    }()
}
