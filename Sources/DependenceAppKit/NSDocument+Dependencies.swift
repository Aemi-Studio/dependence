//
//  NSDocument+Dependencies.swift
//  DependenceAppKit
//
//  Convenience for document-based AppKit composition roots: each document
//  carries its own scoped `DependencyValues`.
//

#if canImport(AppKit)
    import AppKit
    import Dependence
    import ObjectiveC

    extension NSDocument: DependencyHosting {
        /// Storage for the associated-object key.
        ///
        /// The address of this static
        /// `UInt8` is the unique opaque pointer Objective-C uses to key the
        /// associated object — its value is never read or written. We reach for
        /// `nonisolated(unsafe)` because Swift 6 otherwise treats `static var` as
        /// requiring synchronisation; here, the variable is immutable in practice
        /// (only its address matters).
        private nonisolated(unsafe) static var dependenciesKey: UInt8 = 0

        /// The dependency container scoped to this document.
        ///
        /// Visible to the document's window controllers and views. Defaults
        /// to an empty container until set.
        @MainActor
        public var dependencies: DependencyValues {
            get {
                (objc_getAssociatedObject(self, &NSDocument.dependenciesKey) as? Box)?.value ?? .init()
            }
            set {
                objc_setAssociatedObject(
                    self,
                    &NSDocument.dependenciesKey,
                    Box(value: newValue),
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }

        private final class Box: NSObject, @unchecked Sendable {
            let value: DependencyValues
            init(value: DependencyValues) { self.value = value }
        }
    }
#endif
