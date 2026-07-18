//
//  SmallApp.swift
//  ExampleSmallApp
//
//  Thin executable shell. The preview-able UI lives in `ExampleSmallAppCore`
//  so Xcode can host SwiftUI previews — executable targets can't host
//  previews without `ENABLE_DEBUG_DYLIB`, which SwiftPM does not expose.
//

import Dependence
import ExampleSmallAppCore

#if canImport(SwiftUI)
    import SwiftUI

    @main
    struct SmallApp: App {
        var body: some Scene {
            WindowGroup {
                GreetingView()
                    // Subtree override — every descendant resolves through this
                    // container before falling back to the TaskLocal one.
                    .dependencies {
                        $0.apiClient = .live
                    }
            }
        }
    }
#else
    @main
    enum SmallApp {
        static func main() async {
            await withDependencies {
                $0.apiClient = .live
            } operation: {
                let model = await MainActor.run { GreetingViewModel() }
                await model.load()
                await MainActor.run { print(model.greeting) }
            }
        }
    }
#endif
