//
//  PreviewModifier.swift
//  Dependence
//
//  Apple-blessed preview-scoped dependency overrides via `PreviewModifier`.
//

#if canImport(SwiftUI)
    import SwiftUI

    /// A `PreviewModifier` that applies dependency overrides to its content.
    ///
    /// ```swift
    /// #Preview(traits: .modifier(DependencePreview { $0.apiClient = .preview })) {
    ///     RootView()
    /// }
    /// ```
    public struct DependencePreview: PreviewModifier {
        public typealias Context = Void

        private let mutate: (inout DependencyValues) -> Void

        public init(_ mutate: @escaping (inout DependencyValues) -> Void) {
            self.mutate = mutate
        }

        public static func makeSharedContext() async throws -> Context { () }

        public func body(content: Content, context: Context) -> some View {
            content.dependencies(mutate)
        }
    }
#endif
