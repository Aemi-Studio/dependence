//
//  BootstrapTests.swift
//  DependenceTestingTests
//

import Dependence
import DependenceTesting
import Testing

@Suite("Issue-routing bootstrap")
struct BootstrapTests {
    @Test("Constructing any DependenceTesting clock installs Swift Testing issue routing")
    func clockInitInstallsRouting() {
        _ = ImmediateClock()
        // If no handler were installed, the report below would fall through
        // to a runtime warning and `withKnownIssue` would fail with "known
        // issue was not recorded". Caveat for honesty: the once-token is
        // process-wide, so in a full-suite run another entry point (the
        // trait, another clock) may already have installed the handler —
        // this is the strongest in-process pin available, and it is exact
        // when the suite runs in isolation.
        withKnownIssue("routed through Swift Testing") {
            reportIssue("bootstrap probe")
        }
    }
}
