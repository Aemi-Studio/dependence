//
//  HomeView.swift
//  ExampleModularAppCore
//
//  Lives in a library target so SwiftUI Previews work — Xcode 15+ refuses
//  to host previews from executable targets without `ENABLE_DEBUG_DYLIB`,
//  which SwiftPM doesn't expose. The thin `ExampleModularApp` shell wires
//  the live witnesses around an instance of this view.
//

#if canImport(SwiftUI)
    import AuthInterface
    import Dependence
    import FeedInterface
    import ProfileInterface
    import SwiftUI

    @MainActor
    public struct HomeView: View {
        @State private var model = HomeViewModel()

        public init() {}

        public var body: some View {
            VStack(spacing: 16) {
                if let userID = model.userID {
                    Text("Signed in as \(userID)").font(.headline)
                    if let summary = model.profile {
                        Text(summary.displayName).font(.title3)
                        Text(summary.bio).font(.body).foregroundStyle(.secondary)
                    }
                    List(model.feed) { item in
                        Text(item.title)
                    }
                    Button("Sign out") { Task { await model.signOut() } }
                } else {
                    Button("Sign in") { Task { await model.signIn() } }
                }
            }
            .padding()
            .task { await model.signIn() }
        }
    }

    #Preview("Home — preview witnesses") {
        HomeView()
            .dependencies { values in
                values.authClient = .preview
                values.feedClient = .preview
                values.profileClient = .preview
            }
    }
#endif
