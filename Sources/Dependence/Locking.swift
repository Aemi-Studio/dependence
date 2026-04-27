//
//  Locking.swift
//  Dependence
//
//  Internal cross-platform mutex used by storage, lazy values, and detectors.
//

import Synchronization

/// Internal box that protects a `Sendable` value behind a `Mutex`.
///
/// The Swift 6 `Synchronization.Mutex` ships on every platform we target
/// (iOS 18+, macOS 15+, plus Linux when the toolchain is built with the
/// concurrency runtime). We use it in preference to `NSLock`/`os_unfair_lock`
/// because it is non-reentrant by design (matches our usage), zero-allocation,
/// and integrates cleanly with `~Copyable` storage.
@usableFromInline
package struct Locked<Value: ~Copyable & Sendable>: ~Copyable, Sendable {
    @usableFromInline
    let lock: Mutex<Value>

    @inlinable
    package init(_ initial: consuming sending Value) {
        self.lock = Mutex(initial)
    }

    @inlinable
    package borrowing func withLock<R: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending R
    ) throws(E) -> R {
        try lock.withLock(body)
    }
}
