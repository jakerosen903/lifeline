import LifelineKit
import SwiftUI

/// One kind of entity as a list, the root of its tab (Places; People and Things have grids). A free-text tag narrows it.
struct EntityListScreen: View {
    /// Created once per presentation: a parent re-render must not reset the filter.
    @State private var viewModel: EntitiesViewModel
    /// Absent outside the shell (a preview): then nothing watches the session cover.
    @Environment(HomeViewModel.self) private var home: HomeViewModel?
    /// The top page of its stack. Under a cover it stays visible: the cover sends no onDisappear.
    @State private var isVisible = false

    init(deps: Dependencies, type: EntityType) {
        _viewModel = State(initialValue: EntitiesViewModel(deps: deps, type: type))
    }

    var body: some View {
        List {
            Section {
                // Only after the first read: before it, the text would flash over a full list.
                if viewModel.isLoaded, viewModel.rows.isEmpty {
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
        .toolbar { EntityTagFilterMenu(viewModel: viewModel) }
        .onAppear { isVisible = true; viewModel.refresh() }
        .onDisappear { isVisible = false }
        // A session started from this tab lands under a cover; when it closes, read what it added.
        .onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh() } }
    }
}

/// Entity rows that open their pages: the title, then its span.
struct EntityRows: View {
    let rows: [EntitySummary]
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        ForEach(rows) { row in
            NavigationLink {
                EntityScreen(viewModel: EntityViewModel(entity: row.entity, deps: deps), onChange: onChange)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.entity.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    Text(EntityPage.spanText(row.span)).font(.caption).foregroundStyle(Theme.ochreText)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.entity.title)
            }
            .accessibilityIdentifier("entities.row")
        }
    }
}

/// A screen's model that a tag can narrow: the entity lists and the Things shelf.
@MainActor
protocol TagFiltering: AnyObject, Observable {
    var allTags: [String] { get }
    var tagFilter: String? { get set }
}

/// The toolbar menu that narrows a list to one tag. It shows only once a tag exists.
struct EntityTagFilterMenu<Model: TagFiltering>: ToolbarContent {
    let viewModel: Model

    var body: some ToolbarContent {
        ToolbarItem {
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
    }
}
