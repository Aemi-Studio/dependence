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
//  Bootstrap is automatic: any `DependenceTesting` API that ultimately calls
//  `reportIssue` (the `.dependencies` trait, `UnimplementedClock`, etc.)
//  references `_SwiftTestingIssueRouting.bootstrap` once, which registers the
//  handler with `IssueReporter`. After that, any `reportIssue` call made from
//  inside a `@Test` function surfaces as a proper `Issue.record` failure.
//

import Dependence
import Testing

@usableFromInline
enum _SwiftTestingIssueRouting {
    /// Idempotent registration. The closure body runs at most once because
    /// Swift initialises `static let` lazily and atomically; subsequent
    /// references are no-ops.
    @usableFromInline
    static let bootstrap: Void = {
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
