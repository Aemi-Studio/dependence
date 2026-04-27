//
//  GreetingView.swift
//  ExampleSmallAppCore
//
//  Lives in a library target so SwiftUI Previews work — Xcode 15+ refuses
//  to host previews from executable targets without `ENABLE_DEBUG_DYLIB`,
//  which SwiftPM doesn't expose. The thin `ExampleSmallApp` shell in the
//  sibling directory just imports this view from its `@main App` body.
//

#if canImport(SwiftUI)
import Dependence
import SwiftUI

public struct GreetingView: View {
    @State private var model = GreetingViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text(model.greeting)
                .font(.title)
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
            Button("Reload") {
                Task { await model.load() }
            }
        }
        .padding()
        .task { await model.load() }
        .frame(minWidth: 400, minHeight: 400)
    }
}

#Preview("Live witness") {
    GreetingView()
}
#endif
