import LifelineKit
import SwiftUI

/// You: your own page, what you think (ideas), and Settings. A story told from here is about yourself.
struct YouScreen: View {
    /// Created once per presentation: a parent re-render must not reload it.
    @State private var viewModel: EntitiesViewModel
    @State private var showSettings = false
    let isSessionLive: () -> Bool

    init(deps: Dependencies, isSessionLive: @escaping () -> Bool) {
        _viewModel = State(initialValue: EntitiesViewModel(deps: deps, type: .idea))
        self.isSessionLive = isSessionLive
    }

    /// The owner, when the profile has one; with none, the bar says "Tell a story".
    private var ownerSubject: SessionSubject? {
        viewModel.aboutYou.map { SessionSubject(entityID: $0.id, title: $0.title, isOwner: true, excludedFromAI: $0.excludedFromAI) }
    }

    var body: some View {
        List {
            if let you = viewModel.aboutYou {
                Section {
                    NavigationLink {
                        EntityScreen(viewModel: EntityViewModel(entity: you, deps: viewModel.deps)) { viewModel.refresh() }
                    } label: {
                        Text("About you").font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    }
                    .accessibilityIdentifier("entities.aboutYou")
                }
            }
            Section("What you think") {
                if viewModel.rows.isEmpty {
                    Text("Nothing yet. They appear as you tell stories.").foregroundStyle(Theme.secondaryText)
                }
                EntityRows(rows: viewModel.rows, deps: viewModel.deps) { viewModel.refresh() }
            }
            if let error = viewModel.error { Text(error).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle("You")
        .toolbar {
            Button("Settings") { showSettings = true }
                .accessibilityIdentifier("home.settings")
        }
        .sheet(isPresented: $showSettings, onDismiss: { viewModel.refresh() }) {
            SettingsScreen(deps: viewModel.deps, isSessionLive: isSessionLive)
        }
        .onAppear { viewModel.refresh() }
        .sessionContext(ownerSubject)
    }
}
