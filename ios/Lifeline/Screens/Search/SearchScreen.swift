import LifelineKit
import SwiftUI

/// Search, pushed from any tab's Search button (ruling R4): the system's search field, always on screen,
/// then the results grouped by kind (decision 11).
/// An empty field shows one quiet line and nothing else (P9, decision 20).
struct SearchScreen: View {
    /// Created once per presentation: a parent re-render must not reset the query.
    @State private var viewModel: SearchViewModel
    /// Absent outside the shell (a preview): then nothing watches the session cover.
    @Environment(HomeViewModel.self) private var home: HomeViewModel?
    /// The top page of its stack. Under a cover it stays visible: the cover sends no onDisappear.
    @State private var isVisible = false
    /// The field takes focus once, when the screen is first pushed; back from a result it stays as the person left it.
    @FocusState private var isFieldFocused: Bool
    @State private var hasFocused = false

    init(deps: Dependencies) {
        _viewModel = State(initialValue: SearchViewModel(deps: deps))
    }

    var body: some View {
        List {
            if let error = viewModel.error {
                line(error, identifier: "search.error")
            } else if let results = viewModel.results {
                group(.person, results.people)
                group(.place, results.places)
                group(.thing, results.things)
                group(.idea, results.ideas)
            } else {
                // Also before the first read: a query typed then runs when the index is ready.
                line("Search by a name, or by words you said.", identifier: "search.prompt")
            }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle("Search")
        .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Memories, people, places, things")
        .searchFocused($isFieldFocused)
        // Outside `searchable`, so the field reads them: names get "corrected" (decision 19).
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onAppear {
            isVisible = true
            viewModel.refresh()
            if !hasFocused { hasFocused = true; isFieldFocused = true }
        }
        .onDisappear { isVisible = false }
        // A session started from this tab lands under a cover; when it closes, read what it added.
        .onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh() } }
    }

    /// One kind's results under its heading. A kind with no result shows nothing, not an empty heading.
    @ViewBuilder private func group(_ type: EntityType, _ hits: [SearchResults.EntityHit]) -> some View {
        if !hits.isEmpty {
            Section {
                ForEach(hits) { hit in
                    SearchEntityRow(hit: hit, cover: viewModel.covers[hit.id], deps: viewModel.deps) { viewModel.refresh() }
                }
            } header: {
                Text(SearchResults.heading(type))
                    .sectionHeadingStyle()
                    .accessibilityIdentifier("search.heading")
            }
        }
    }

    private func line(_ text: String, identifier: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.secondaryText)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier(identifier)
    }
}
