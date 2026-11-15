import LifelineKit
import SwiftUI

/// One kind of entity (People, Places or Things), the root of its tab. A free-text tag narrows it.
struct EntityListScreen: View {
    /// Created once per presentation: a parent re-render must not reset the filter.
    @State private var viewModel: EntitiesViewModel

    init(deps: Dependencies, type: EntityType) {
        _viewModel = State(initialValue: EntitiesViewModel(deps: deps, type: type))
    }

    var body: some View {
        List {
            Section {
                if viewModel.rows.isEmpty {
                    Text(viewModel.tagFilter == nil ? "Nothing yet. They appear as you tell stories." : "Nothing tagged “\(viewModel.tagFilter!)”.")
                        .foregroundStyle(Theme.secondaryText)
                }
                EntityRows(rows: viewModel.rows, deps: viewModel.deps) { viewModel.refresh() }
            }
            if let error = viewModel.error { Text(error).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle(viewModel.type.screenTitle)
        .toolbar {
            if !viewModel.allTags.isEmpty {
                Menu {
                    Button("Everything") { viewModel.tagFilter = nil }
                    ForEach(viewModel.allTags, id: \.self) { tag in
                        Button { viewModel.tagFilter = tag } label: {
                            if viewModel.tagFilter == tag { Label(tag, systemImage: "checkmark") } else { Text(tag) }
                        }
                        .accessibilityIdentifier("entities.tag.\(tag)")
                    }
                } label: { Image(systemName: viewModel.tagFilter == nil ? "tag" : "tag.fill") }
                    .accessibilityLabel(viewModel.tagFilter.map { "Showing \($0)" } ?? "Filter by tag")
                    .accessibilityIdentifier("entities.tagFilter")
            }
        }
        .onAppear { viewModel.refresh() }
    }
}

/// Entity rows that open their pages: the title, then its span.
struct EntityRows: View {
    let rows: [EntitiesViewModel.Row]
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        ForEach(rows) { row in
            NavigationLink {
                EntityScreen(viewModel: EntityViewModel(entity: row.entity, deps: deps), onChange: onChange)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.entity.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    Text(row.spanText).font(.caption).foregroundStyle(Theme.ochreText)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.entity.title)
            }
            .accessibilityIdentifier("entities.row")
        }
    }
}
