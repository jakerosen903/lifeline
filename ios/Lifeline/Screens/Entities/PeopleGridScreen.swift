import LifelineKit
import SwiftUI

/// People, the root of its tab: a grid of monogram tiles, three to a row, two at the first
/// accessibility sizes and a list from the third. A free-text tag narrows it; a menu sorts it.
struct PeopleGridScreen: View {
    /// Created once per presentation: a parent re-render must not reset the filter.
    @State private var viewModel: EntitiesViewModel
    /// Starts on "Most told" at each launch; it is not remembered (plan decision 10).
    @State private var sort: PeopleSort = .mostTold
    @Environment(\.dynamicTypeSize) private var textSize
    /// Absent outside the shell (a preview): then nothing watches the session cover.
    @Environment(HomeViewModel.self) private var home: HomeViewModel?
    /// The top page of its stack. Under a cover it stays visible: the cover sends no onDisappear.
    @State private var isVisible = false

    init(deps: Dependencies) {
        _viewModel = State(initialValue: EntitiesViewModel(deps: deps, type: .person))
    }

    var body: some View {
        let people = sort.sorted(viewModel.rows)
        Group {
            if people.isEmpty {
                empty
            } else if textSize >= .accessibility3 {
                list(people)
            } else {
                grid(people)
            }
        }
        .linenBackground()
        .navigationTitle(viewModel.type.screenTitle)
        .toolbar {
            EntityTagFilterMenu(viewModel: viewModel)
        }
        .onAppear { isVisible = true; viewModel.refresh() }
        .onDisappear { isVisible = false }
        // A session started from this tab lands under a cover; when it closes, read what it added.
        .onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh() } }
    }

    private var columns: [GridItem] {
        let count = textSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
    }

    private func grid(_ people: [EntitySummary]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sortMenu.padding(.horizontal, 16)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(people) { PersonTile(summary: $0, deps: viewModel.deps) { viewModel.refresh() } }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .accessibilityIdentifier("people.grid")
                errorLine
            }
        }
    }

    private func list(_ people: [EntitySummary]) -> some View {
        List {
            sortMenu.listRowBackground(Color.clear)
            ForEach(people) { PersonRow(summary: $0, deps: viewModel.deps) { viewModel.refresh() } }
            errorLine
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("people.list")
    }

    private var empty: some View {
        List {
            // Only after the first read: before it, the text would flash over a full grid.
            if viewModel.isLoaded {
                Text(viewModel.tagFilter.map { "Nothing tagged “\($0)”." } ?? "Nothing yet. They appear as you tell stories.")
                    .foregroundStyle(Theme.secondaryText)
            }
            errorLine
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var errorLine: some View {
        if let error = viewModel.error { Text(error).foregroundStyle(.red) }
    }

    /// The first item in the scrolling content, not a pinned row: at the largest text sizes a
    /// pinned row and the title took a third of the screen. Not a toolbar item either: the bar
    /// shows a bare icon, and the current sort is state the person should see.
    private var sortMenu: some View {
        Menu {
            ForEach(PeopleSort.allCases, id: \.self) { option in
                Button { sort = option } label: {
                    if sort == option { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
                .accessibilityIdentifier("people.sort.\(option.rawValue)")
            }
        } label: {
            Label(sort.title, systemImage: "arrow.up.arrow.down")
                .labelStyle(.titleAndIcon).font(.subheadline.weight(.medium)).foregroundStyle(Theme.oliveText)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(sort.title)
        .accessibilityHint("Changes the order of people")
        .accessibilityIdentifier("people.sort")
    }
}
