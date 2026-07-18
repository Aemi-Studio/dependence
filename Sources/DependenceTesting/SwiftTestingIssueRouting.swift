//
//  SwiftTestingIssueRouting.swift
//  DependenceTesting
//
//  Bridges `Dependence.reportIssue(_:)` to Swift Testing's `Issue.record`.
//
//  The core `Dependence` library is Foundation-only and intentionally does
//  **not** link `Testing.framework` — embedding it into a non-test executable
//  would crash the app at launch. `DependenceTesting` is allowed to link
//  `Testing.framework` because it only ships in test bundles, so we install
//  the Swift-Testing-aware handler from here.
//
//  Bootstrap is automatic: EVERY public entry point of this module — the
//  `.dependencies` trait and all three clocks' initializers — touches
//  `Bootstrap.once`, so linking and using the module in any form registers
//  the handler. (There is no Swift mechanism for running code at plain
//  module-load time without ObjC machinery, so an entry-point touch is the
//  strongest guarantee available; a test process that imports the module but
//  never constructs any of its types has, by definition, nothing routed
//  through it either.) After the touch, any `reportIssue` call made from
//  inside a `@Test` function surfaces as a proper `Issue.record` failure.
//

import Dependence
import Testing

/// Registers the Swift Testing issue handler exactly once per process.
@usableFromInline
enum Bootstrap {
    /// Idempotent registration.
    ///
    /// The closure body runs at most once because Swift initialises
    /// `static let` lazily and atomically; subsequent references are no-ops.
    /// `IssueReporter.register(_:)` appends without deduplication, so this
    /// single once-token is the module's only registration path — every
    /// entry point funnels through it.
    @usableFromInline
    static let once: Void = {
        IssueReporter.register { message, fileID, filePath, line, column in
            // Only claim the issue when we're actually inside a running test.
            // If `Test.current` is nil (e.g. a `reportIssue` triggered during
            // test-bundle load or a helper invoked outside a `@Test`), let
            // `reportIssue` fall through to its other sinks.
            guard Test.current != nil else { return false }
            Issue.record(
                Comment(rawValue: message),
                sourceLocation: SourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
            return true
        }
    }()
}
