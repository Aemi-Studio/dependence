//
//  TaskPropagationTests.swift
//  DependenceTests
//
//  Pins down `Task { … }`/`withTaskGroup` propagation. `@TaskLocal` values
//  copy into structured children at task creation. `Task { … }` is
//  unstructured but, per Swift Concurrency Evolution, it inherits the
//  surrounding task's task-local values at construction. `Task.detached`
//  does not. These tests prove the distinction is preserved by `Dependence`
//  (which only ever binds `DependencyValues._current` via a `@TaskLocal`).
//

import Dependence
import DependenceTesting
import Foundation
import Testing

@Suite("Task and task-group propagation")
struct TaskPropagationTests {

    private struct Token: Sendable, Equatable { var name: String }

    private enum TokenKey: DependencyKey {
        static var liveValue: Token { Token(name: "live") }
        static var testValue: Token { Token(name: "test") }
    }

    @Test("Task { } inherits the surrounding withDependencies binding")
    func unstructuredTaskInheritsBinding() async {
        let observed: Token = await withDependencies {
            $0[TokenKey.self] = Token(name: "outer")
        } operation: {
            // `Task { }` captures the surrounding task-local stack at
            // construction. The await blocks the outer scope until the
            // child's read completes — task-local lookup is instantaneous so
            // the binding is still in scope.
            await Task {
                DependencyValues.current[TokenKey.self]
            }.value
        }

        #expect(observed == Token(name: "outer"))
    }

    @Test("Task { } observes the binding even when awaited after the scope returns")
    func unstructuredTaskRetainsCapturedBinding() async {
        // Because `Task { }` snapshots task-local values at construction, the
        // child sees the override even if the parent withDependencies block
        // has already returned by the time we read the child's `value`.
        let task: Task<Token, Never> = withDependencies {
            $0[TokenKey.self] = Token(name: "captured")
        } operation: {
            Task {
                // Yield once so the child certainly executes after the parent
                // closure has returned.
                await Task.yield()
                return DependencyValues.current[TokenKey.self]
            }
        }

        let observed = await task.value
        #expect(observed == Token(name: "captured"))
    }

    @Test("withTaskGroup.addTask propagates the override to every child")
    func taskGroupAddTaskPropagates() async {
        let observed: [Token] = await withDependencies {
            $0[TokenKey.self] = Token(name: "group")
        } operation: {
            await withTaskGroup(of: Token.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        DependencyValues.current[TokenKey.self]
                    }
                }
                var collected: [Token] = []
                for await value in group {
                    collected.append(value)
                }
                return collected
            }
        }

        #expect(observed == Array(repeating: Token(name: "group"), count: 4))
    }

    @Test("withThrowingTaskGroup propagates the override")
    func throwingTaskGroupPropagates() async throws {
        let observed: Token = try await withDependencies {
            $0[TokenKey.self] = Token(name: "throwing")
        } operation: {
            try await withThrowingTaskGroup(of: Token.self) { group in
                group.addTask {
                    DependencyValues.current[TokenKey.self]
                }
                guard let value = try await group.next() else {
                    Issue.record("task group produced no value")
                    return Token(name: "missing")
                }
                return value
            }
        }

        #expect(observed == Token(name: "throwing"))
    }
}
