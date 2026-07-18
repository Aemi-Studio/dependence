//
//  Observation+UIKit.swift
//  DependenceUIKit
//
//  Helpers for participating in iOS 26's automatic UIKit observation
//  tracking. With `UIObservationTrackingEnabled = YES` (the default in
//  iOS 26 SDK), `viewWillLayoutSubviews` / `layoutSubviews` automatically
//  open an observation tracking scope. These helpers cover the cases that
//  do not — explicit one-shot reads.
//

#if canImport(UIKit)
    import Dependence
    import Observation
    import UIKit

    extension UIViewController {
        /// Read the active dependencies, observing what `body` accesses.
        ///
        /// Any `@Observable` access performed by `body` is tracked. When an
        /// observed value changes, `onChange` is invoked once on the main
        /// actor, after which you typically reschedule by calling this
        /// helper again.
        @MainActor
        public func withObservedDependencies<R>(
            _ body: (DependencyValues) -> R,
            onChange: @escaping @MainActor () -> Void
        ) -> R {
            let values = traitCollection.dependencies
            return withObservationTracking {
                body(values)
            } onChange: {
                Task { @MainActor in onChange() }
            }
        }
    }
#endif
