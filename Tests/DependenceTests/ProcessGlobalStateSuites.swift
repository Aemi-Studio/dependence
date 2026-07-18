//
//  ProcessGlobalStateSuites.swift
//  DependenceTests
//
//  Umbrella suite for tests that mutate process-wide state (the resolution
//  cache, the SwiftUI subtree stack, the prepareDependencies latch).
//
//  `.serialized` on a suite only serializes the tests *within* that suite —
//  two sibling `.serialized` suites still interleave with each other, and
//  suites that both call `DependencyRuntimeState.resetForTesting()` then
//  stomp each other's cache mid-test. The trait is recursive, so nesting
//  the suites under this umbrella serializes all of their tests against
//  one another.
//

import Testing

@Suite("Process-global state", .serialized)
enum ProcessGlobalStateSuites {}
