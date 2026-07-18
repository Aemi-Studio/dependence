//
//  ModularApp.swift
//  ExampleModularApp
//
//  Thin executable shell. The preview-able UI lives in
//  `ExampleModularAppCore` so Xcode can host SwiftUI previews — executable
//  targets can't host previews without `ENABLE_DEBUG_DYLIB`, which SwiftPM
//  does not expose. This is the only target that imports every `*Impl`
//  module — features see only the `*Interface` modules of their
//  collaborators, so cross-feature coupling is impossible.
//

import AuthImpl
import Dependence
import ExampleModularAppCore
import FeedImpl
import ProfileImpl

#if canImport(SwiftUI)
    import SwiftUI

    @main
    struct ModularApp: App {
        init() {
            prepareDependencies { dependencies in
                // Wire the live values explicitly. Importing the *Impl
                // modules is what makes `.live` resolvable here — the
                // feature targets themselves cannot do this.
                dependencies.authClient = .live
                dependencies.feedClient = .live
                dependencies.profileClient = .live
            }
        }

        var body: some Scene {
            WindowGroup {
                HomeView()
            }
        }
    }
#else
    @main
    enum ModularApp {
        static func main() async {
            await withDependencies {
                $0.authClient = .live
                $0.feedClient = .live
                $0.profileClient = .live
            } operation: {
                let model = await MainActor.run { HomeViewModel() }
                await model.signIn()
                await MainActor.run {
                    print("user:", model.userID ?? "<nil>")
                    print("profile:", model.profile?.displayName ?? "<nil>")
                    print("feed count:", model.feed.count)
                }
            }
        }
    }
#endif
