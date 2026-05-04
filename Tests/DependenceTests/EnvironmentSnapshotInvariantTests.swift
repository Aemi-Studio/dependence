//
//  EnvironmentSnapshotInvariantTests.swift
//  DependenceTests
//
//  Static invariant for G6: `_environmentValues` (the `@Environment(\.dependencies)`
//  read) must only be consulted inside `DynamicProperty.update()`. Reading it
//  from `wrappedValue` (or any other site) emits the SwiftUI runtime warning
//  "Accessing Environment<...>'s value outside of being installed on a View"
//  and silently returns the default container.
//
//  We can't capture the SwiftUI runtime warning from a unit test, so we
//  verify the invariant at the source level: there must be exactly one
//  textual reference to `_environmentValues` in `Dependency.swift`, and it
//  must live inside `update()`.
//

#if canImport(SwiftUI)
import Foundation
import Testing

@Suite("Environment-snapshot read invariant (G6)")
struct EnvironmentSnapshotInvariantTests {

    @Test("`_environmentValues` is only read from inside DynamicProperty.update()")
    func environmentValuesReadIsLocalised() throws {
        // Resolve the source path relative to this test file. `#filePath`
        // gives us an absolute path that survives wherever the package is
        // checked out.
        let here = URL(fileURLWithPath: #filePath)
        let packageRoot = here
            .deletingLastPathComponent() // EnvironmentSnapshotInvariantTests.swift
            .deletingLastPathComponent() // DependenceTests
            .deletingLastPathComponent() // Tests
        let dependencySource = packageRoot
            .appendingPathComponent("Sources/Dependence/Dependency.swift")

        let source = try String(contentsOf: dependencySource, encoding: .utf8)

        // Three reference sites are expected:
        //   1. `@Environment(\.dependencies) … var _environmentValues` (declaration)
        //   2. `let snapshot = _environmentValues` (read inside `update()`)
        //   3. The doc-comment that names the property in `Dependency`'s
        //      header. We allow doc references but require any executable
        //      read to live inside `update()`.
        //
        // We extract the function body of `update()` and assert that any
        // *non-declaration, non-comment* reference to `_environmentValues`
        // is inside it.

        let updateBody = try #require(
            extractFunctionBody(named: "update", from: source),
            "update() body not found in Dependency.swift"
        )

        // Strip line comments so doc/inline mentions don't count as reads.
        let nonCommentSource = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if let commentStart = line.range(of: "//") {
                    return String(line[..<commentStart.lowerBound])
                }
                return String(line)
            }
            .joined(separator: "\n")

        // Collapse whitespace so we can look for `_environmentValues` as a
        // standalone identifier reference.
        let identifier = "_environmentValues"
        let totalReferences = nonCommentSource.components(separatedBy: identifier).count - 1
        let referencesInsideUpdate = updateBody.components(separatedBy: identifier).count - 1

        // We expect exactly one declaration (`var _environmentValues`) and
        // exactly one read inside `update()`. Anything else is either dead
        // code or a violation that would re-introduce the runtime warning.
        let declarationReferences = totalReferences - referencesInsideUpdate
        #expect(declarationReferences == 1, "expected exactly one declaration of `_environmentValues`")
        #expect(referencesInsideUpdate == 1, "expected exactly one read of `_environmentValues` inside update()")
    }

    /// Naive, deliberate brace-matching extractor. Returns the body of the
    /// first function whose declaration line contains `func <name>` —
    /// adequate for `Dependency.swift` which has a single `update()`.
    private func extractFunctionBody(named name: String, from source: String) -> String? {
        let needle = "func \(name)"
        guard let funcRange = source.range(of: needle) else { return nil }
        guard let openBrace = source.range(of: "{", range: funcRange.upperBound..<source.endIndex) else {
            return nil
        }

        var depth = 1
        var index = openBrace.upperBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBrace.upperBound..<index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
#endif
