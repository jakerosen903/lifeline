import LifelineKit
import SwiftUI

/// People, Places, Things, Ideas (M7): a segmented control, not four tabs.
struct EntitiesScreen: View {
    @Bindable var viewModel: EntitiesViewModel

    var body: some View {
        List {
            Section {
                Picker("Kind", selection: $viewModel.type) {
                    ForEach(EntityType.allCases, id: \.self) { Text($0.screenTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("entities.type")
                .listRowBackground(Color.clear)
            }
            Section {
                if viewModel.rows.isEmpty {
                    Text(viewModel.tagFilter == nil ? "Nothing yet. They appear as you tell stories." : "Nothing tagged “\(viewModel.tagFilter!)”.")
                        .foregroundStyle(Theme.stone)
                }
                ForEach(viewModel.rows) { row in
                    NavigationLink {
                        EntityScreen(viewModel: EntityViewModel(entity: row.entity, deps: viewModel.deps)) { viewModel.refresh() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.entity.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                            Text(row.spanText).font(.caption).foregroundStyle(Theme.ochre)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.entity.title)
                    }
                    .accessibilityIdentifier("entities.row")
                }
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
