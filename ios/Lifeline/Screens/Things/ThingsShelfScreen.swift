import LifelineKit
import SwiftUI

/// Things, the root of its tab: a shelf of tiles grouped by life period, oldest first, then
/// "Not placed in time yet". With no placed thing it is one grid with no heading. It shows no
/// count of things and no "add" control (P9). A free-text tag narrows it.
struct ThingsShelfScreen: View {
    /// Created once per presentation: a parent re-render must not reset the filter.
    @State private var viewModel: ThingsShelfViewModel
    @Environment(\.dynamicTypeSize) private var textSize
    /// Absent outside the shell (a preview): then nothing watches the session cover.
    @Environment(HomeViewModel.self) private var home: HomeViewModel?
    /// The top page of its stack. Under a cover it stays visible: the cover sends no onDisappear.
    @State private var isVisible = false

    init(deps: Dependencies) {
        _viewModel = State(initialValue: ThingsShelfViewModel(deps: deps))
    }

    var body: some View {
        content
            .linenBackground()
            .navigationTitle("Things")
            .toolbar { EntityTagFilterMenu(viewModel: viewModel) }
            .onAppear { isVisible = true; viewModel.refresh() }
            .onDisappear { isVisible = false }
            // A session started from this tab lands under a cover; when it closes, read what it added.
            .onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh() } }
    }

    @ViewBuilder private var content: some View {
        if let error = viewModel.error {
            line(error, colour: .red, identifier: "things.error")
        } else if viewModel.isLoaded, viewModel.isEmpty {
            line(viewModel.tagFilter.map { "Nothing tagged “\($0)”." } ?? "Nothing yet. They appear as you tell stories.",
                 colour: Theme.secondaryText, identifier: "things.empty")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    switch viewModel.layout {
                    case .flat(let tiles):
                        grid(tiles)
                    case .grouped(let groups):
                        ForEach(groups, id: \.heading.text) { group in
                            heading(group.heading)
                            grid(group.tiles).padding(.bottom, 12)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .accessibilityIdentifier("things.grid")
        }
    }

    /// Two columns; one at the accessibility text sizes, where each tile grows to fit its text.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: textSize.isAccessibilitySize ? 1 : 2)
    }

    private func grid(_ tiles: [ThingShelf.Tile]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(tiles) { tile in
                let photo = viewModel.keyPhotos[tile.id]
                ThingTile(tile: tile, keyPhoto: photo, quote: photo == nil ? viewModel.quotes[tile.id] : nil,
                          deps: viewModel.deps) { viewModel.refresh() }
            }
        }
    }

    private func heading(_ heading: ThingShelf.Heading) -> some View {
        Text(heading.text)
            .sectionHeadingStyle()
            .padding(.top, 8)
            .accessibilityIdentifier(heading == .notPlaced ? "things.unplaced" : "things.period")
    }

    private func line(_ text: String, colour: Color, identifier: String) -> some View {
        Text(text)
            .foregroundStyle(colour)
            .accessibilityIdentifier(identifier)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
