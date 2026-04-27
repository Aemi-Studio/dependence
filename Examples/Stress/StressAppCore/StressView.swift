//
//  StressView.swift
//  ExampleStressAppCore
//

#if canImport(SwiftUI)
import Dependence
import SwiftUI

public struct StressView: View {
    @State private var model = StressViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("State", value: model.status)
                    LabeledContent("Refreshes", value: String(model.refreshCount))
                    if let error = model.lastError {
                        LabeledContent("Error", value: error).foregroundStyle(.red)
                    }
                }
                Section("Profile") {
                    LabeledContent("Name", value: model.profileName)
                }
                Section("Search hits") {
                    ForEach(model.searchHits, id: \.self) { Text($0) }
                }
                Section("Feed") {
                    ForEach(model.feed, id: \.id) { item in
                        LabeledContent("#\(item.id)", value: item.title)
                    }
                }
            }
            .navigationTitle("Stress")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { Task { await model.refresh() } }
                }
            }
            .task { await model.refresh() }
        }
    }
}

// Auto-resolved preview witnesses — `#Preview` runs in `IssueContext.preview`,
// so the resolver dispatches generically to `K.previewValue`. Because every
// `@DependencyEntry(preview: .preview)` stamps that witness directly into the
// conformance, no modifier is required here.
#Preview("Auto-resolved preview witnesses") {
    StressView()
}

// Per-call subtree overrides still compose on top of the auto-resolved base.
// We override `searchService` (a witness exposed via `@DependencyClient`-free
// init) so the modifier's value flows through the live call path at refresh
// time — proves the resolver picks up the override mid-graph, not just at
// the leaf.
#Preview("Subtree override on top of auto-resolution") {
    StressView()
        .dependencies {
            $0.profileHTTPClient = .live
            $0.profileService = .live
            $0.searchService = .live
            $0.searchHTTPClient = .live
            $0.feedService = .live
            $0.feedHTTPClient = .live
        }
}
#endif
