//
//  Lazy.swift
//  Dependence
//
//  One-shot lazy initialization wrapper, `Sendable`-safe.
//

import Foundation
import Synchronization

/// A `Sendable`-safe one-shot lazy.
///
/// Construct with a `@Sendable` closure; the first installed result is
/// cached and every subsequent read returns that value without re-entering
/// the closure.
///
/// Useful for breaking initialization cycles inside witnesses or for
/// expressing "expensive singleton, defer construction".
///
/// The producer is evaluated outside the internal lock so it can safely read
/// other dependencies or lazy values. Under contention, more than one caller
/// may run the producer, but only the first value installed under the lock is
/// stored. Keep producer closures side-effect-safe.
public struct Lazy<Value: Sendable>: Sendable {
    private let storage: Storage

    public init(_ make: @escaping @Sendable () -> Value) {
        self.storage = Storage(make)
    }

    /// Force evaluation and return the value.
    public func callAsFunction() -> Value { storage.read() }

    private final class Storage: @unchecked Sendable {
        private enum State {
            case unevaluated(@Sendable () -> Value)
            case evaluated(Value)
        }

        private let lock: Mutex<State>

        init(_ make: @escaping @Sendable () -> Value) {
            self.lock = Mutex(.unevaluated(make))
        }

        func read() -> Value {
            // Phase 1: locked peek. Cheap on the hot path. The switch is
            // exhaustive — the previous guard-with-fallback re-read was dead
            // code dressed up as caution.
            let make: @Sendable () -> Value
            switch lock.withLock({ $0 }) {
                case .evaluated(let value):
                    return value
                case .unevaluated(let producer):
                    make = producer
            }
            // Phase 2: compute outside the lock so a `make` closure that
            // re-enters another `Lazy` (or a `@Dependency` resolution) does
            // not deadlock on this lock.
            let computed = make()
            // Phase 3: locked install with double-check. Under contention a
            // racing caller may have already installed a value; return that
            // one so first-installed semantics are deterministic.
            return lock.withLock { state in
                if case .evaluated(let existing) = state {
                    return existing
                }
                state = .evaluated(computed)
                return computed
            }
        }
    }
}
