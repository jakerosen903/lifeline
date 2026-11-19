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
    /// The search is active: the bar shows "Close" in place of Back. Return, scrolling and a pushed page keep it active.
    /// It becomes active once, when the screen is first pushed. When the person closes it, search closes (ruling R5).
    @State private var isActive = false
    @State private var hasActivated = false
    /// The query whose "nothing found" was last announced: each query is announced once (decision 26).
    @State private var announcedQuery: String?
    /// Pops search off its tab's stack.
    let close: () -> Void

    init(deps: Dependencies, close: @escaping () -> Void) {
        self.close = close
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
                memories(results.memories)
                if results.isEmpty { nothingFound }
            } else {
                // Also before the first read: a query typed then runs when the index is ready.
                line("Search by a name, or by words you said.", identifier: "search.prompt")
            }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle("Search")
        .searchable(text: $viewModel.query, isPresented: $isActive, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Memories, people, places, things")
        // Outside `searchable`, so the field reads them: names get "corrected" (decision 19).
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onAppear {
            isVisible = true
            viewModel.refresh()
            if !hasActivated { hasActivated = true; isActive = true }
        }
        .onDisappear { isVisible = false }
        // "Close" ends the search, and the search is the whole screen: one tap leads back to the tab.
        .onChange(of: isActive) { _, active in if !active && hasActivated { closeAfterTheBarSettles() } }
        .onChange(of: viewModel.results) { announceNothingFound() }
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

    /// After Return, "Close" turns the search off at once, and a pop asked for while the bar redraws is dropped
    /// (seen in the iOS 26.3 simulator: 50 ms is too soon, 500 ms works). So the pop waits for the bar.
    /// A field tapped again in the meantime, or a screen already left, keeps the screen as it is.
    private func closeAfterTheBarSettles() {
        Task {
            try? await Task.sleep(for: Self.barTransition)
            if !isActive && isVisible { close() }
        }
    }

    private static let barTransition = Duration.milliseconds(500)

    /// Memories found by their title or by the words said, in life order (decision 12), after the entity groups.
    @ViewBuilder private func memories(_ hits: [SearchResults.MemoryHit]) -> some View {
        if !hits.isEmpty {
            Section {
                ForEach(hits) { hit in
                    SearchMemoryRow(hit: hit, query: viewModel.query, deps: viewModel.deps) { viewModel.refresh() }
                }
            } header: {
                Text(SearchResults.memoriesHeading)
                    .sectionHeadingStyle()
                    .accessibilityIdentifier("search.heading")
            }
        }
    }

    /// What search looks at, so the person is never told the words were not said (decision 18). No button (P9).
    private var nothingFound: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing found")
                .font(.headline).foregroundStyle(Theme.ink)
                .accessibilityIdentifier("search.none")
            Text("Search looks at names and at the words of memories you kept.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .listRowBackground(Color.clear)
    }

    /// VoiceOver hears "Nothing found" once for each query that finds nothing, not again when the same query is read again.
    private func announceNothingFound() {
        guard viewModel.results?.isEmpty == true, announcedQuery != viewModel.query else { return }
        announcedQuery = viewModel.query
        AccessibilityNotification.Announcement("Nothing found").post()
    }

    private func line(_ text: String, identifier: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.secondaryText)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier(identifier)
    }
}
