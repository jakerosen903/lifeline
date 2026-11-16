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
            ToolbarItem { sortMenu }
        }
        .onAppear { viewModel.refresh() }
    }

    private var columns: [GridItem] {
        let count = textSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
    }

    private func grid(_ people: [EntitySummary]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(people) { PersonTile(summary: $0, deps: viewModel.deps) { viewModel.refresh() } }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .accessibilityIdentifier("people.grid")
            errorLine
        }
    }

    private func list(_ people: [EntitySummary]) -> some View {
        List {
            ForEach(people) { PersonRow(summary: $0, deps: viewModel.deps) { viewModel.refresh() } }
            errorLine
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("people.list")
    }

    private var empty: some View {
        List {
            Text(viewModel.tagFilter.map { "Nothing tagged “\($0)”." } ?? "Nothing yet. They appear as you tell stories.")
                .foregroundStyle(Theme.secondaryText)
            errorLine
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var errorLine: some View {
        if let error = viewModel.error { Text(error).foregroundStyle(.red) }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PeopleSort.allCases, id: \.self) { option in
                Button { sort = option } label: {
                    if sort == option { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
                .accessibilityIdentifier("people.sort.\(option.rawValue)")
            }
        } label: { Label(sort.title, systemImage: "arrow.up.arrow.down") }
            .accessibilityIdentifier("people.sort")
    }
}
