//
//  OffloadBoundaryTests.swift
//  DependenceTests
//
//  Boundaries that do **not** propagate `@TaskLocal` and therefore require
//  explicit `captureDependencies()` to keep overrides visible:
//
//    - GCD (`DispatchQueue.async`)
//    - NotificationCenter callbacks
//    - `AsyncStream` continuations whose producer escapes the task tree
//    - `Task.detached`
//
//  Each test does the same thing: install an override, capture, cross the
//  boundary, then read the captured override on the other side. The
//  asymmetric "no-capture" cases prove the boundary really doesn't
//  propagate by itself — protecting the assertion against a future
//  regression where `captureDependencies` becomes a no-op and the test
//  still passes for the wrong reason.
//

import Dependence
import DependenceTesting
import Foundation
import Testing

@Suite("Offload boundaries", .serialized)
struct OffloadBoundaryTests {
    private struct Beacon: Sendable, Equatable { var value: String }

    private enum BeaconKey: DependencyKey {
        static var liveValue: Beacon { Beacon(value: "live") }
        static var testValue: Beacon { Beacon(value: "test") }
    }

    // MARK: - GCD

    @Test("GCD: captureDependencies bridges DispatchQueue.async")
    func gcdWithCapture() async {
        let observed = await withDependencies {
            $0[BeaconKey.self] = Beacon(value: "gcd")
        } operation: {
            let continuation = captureDependencies()
            return await withCheckedContinuation { (cc: CheckedContinuation<Beacon, Never>) in
                DispatchQueue.global().async {
                    continuation.yield {
                        cc.resume(returning: DependencyValues.current[BeaconKey.self])
                    }
                }
            }
        }

        #expect(observed == Beacon(value: "gcd"))
    }

    @Test("GCD: without captureDependencies the override does not propagate")
    func gcdWithoutCaptureDropsOverride() async {
        let observed = await withDependencies {
            $0[BeaconKey.self] = Beacon(value: "gcd-orphan")
        } operation: {
            await withCheckedContinuation { (cc: CheckedContinuation<Beacon, Never>) in
                DispatchQueue.global().async {
                    cc.resume(returning: DependencyValues.current[BeaconKey.self])
                }
            }
        }

        // GCD blocks have no notion of `@TaskLocal`. The override is gone.
        #expect(observed == Beacon(value: "test"))
    }

    // MARK: - NotificationCenter

    @Test("NotificationCenter: capture bridges into a posted observer")
    func notificationCenterWithCapture() async {
        let center = NotificationCenter()
        let name = Notification.Name("test.dependence.offload.notification")

        let observed: Beacon = await withDependencies {
            $0[BeaconKey.self] = Beacon(value: "notif")
        } operation: {
            let continuation = captureDependencies()
            return await withCheckedContinuation { (cc: CheckedContinuation<Beacon, Never>) in
                // Use the older add/remove pair so the observer outlives this
                // closure and removeObserver can run after we resume. The
                // sentinel object discriminates this observer from any other
                // posted on the same name.
                let observer = NSObject()
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil
                ) { _ in
                    continuation.yield {
                        cc.resume(returning: DependencyValues.current[BeaconKey.self])
                    }
                }
                center.post(name: name, object: observer)
            }
        }

        #expect(observed == Beacon(value: "notif"))
    }

    // MARK: - AsyncStream

    @Test("AsyncStream: capture lets the producer side rebind the override")
    func asyncStreamProducerCapture() async {
        let observed: Beacon = await withDependencies {
            $0[BeaconKey.self] = Beacon(value: "stream")
        } operation: { () async -> Beacon in
            let continuation = captureDependencies()
            let stream = AsyncStream<Beacon> { stream in
                // The producer side runs on a detached cooperative task that
                // does not inherit our task locals; we rebind via the
                // captured continuation.
                Task.detached {
                    continuation.yield {
                        stream.yield(DependencyValues.current[BeaconKey.self])
                        stream.finish()
                    }
                }
            }
            for await value in stream { return value }
            Issue.record("AsyncStream finished without yielding")
            return Beacon(value: "missing")
        }

        #expect(observed == Beacon(value: "stream"))
    }

    // MARK: - Task.detached

    @Test("Task.detached without capture loses the override")
    func detachedWithoutCaptureDropsOverride() async {
        let observed: Beacon = await withDependencies {
            $0[BeaconKey.self] = Beacon(value: "detached-orphan")
        } operation: {
            await Task.detached {
                DependencyValues.current[BeaconKey.self]
            }.value
        }
        #expect(observed == Beacon(value: "test"))
    }

    @Test("Task.detached with capture sees the override")
    func detachedWithCaptureSeesOverride() async {
        let observed: Beacon = await withDependencies {
            $0[BeaconKey.self] = Beacon(value: "detached-bound")
        } operation: {
            let continuation = captureDependencies()
            return await Task.detached {
                continuation.yield {
                    DependencyValues.current[BeaconKey.self]
                }
            }.value
        }
        #expect(observed == Beacon(value: "detached-bound"))
    }
}
