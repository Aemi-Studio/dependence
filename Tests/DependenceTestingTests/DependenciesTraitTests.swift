//
//  DependenciesTraitTests.swift
//  DependenceTestingTests
//

import Dependence
import DependenceTesting
import Testing

@Suite(
    "DependenciesTrait",
    .dependencies { values in
        values[TraitKey.self] = "from-suite"
    })
struct DependenciesTraitTests {
    @Test("Suite-level trait is applied")
    func suiteLevel() {
        #expect(DependencyValues.current[TraitKey.self] == "from-suite")
    }

    @Test("Test-level trait overrides suite-level", .dependencies { $0[TraitKey.self] = "from-test" })
    func testLevel() {
        #expect(DependencyValues.current[TraitKey.self] == "from-test")
    }
}

enum TraitKey: DependencyKey {
    static var liveValue: String { "live" }
    static var testValue: String { "default" }
}
