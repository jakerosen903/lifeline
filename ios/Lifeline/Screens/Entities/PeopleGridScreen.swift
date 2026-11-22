import LifelineKit
import SwiftUI

/// People, the root of its tab: a grid of tiles (a cover photo, else a monogram), three to a row, two at the first
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tile a face is dragged over: it shows the drop ring.
    @State private var dropTarget: EntityID?
    /// Open while the owner is asked "Same person?" about a dropped pair.
    @State private var askingSamePerson = false
    /// The merge "Merge" wrote, held until the sheet is gone so the motion shows on the grid.
    @State private var merged: PersonMergeReceipt?
    /// The pair just merged, while the tile that left shrinks into the one that stays (plan decision 10).
    @State private var vanishing: (leaving: EntityID, staying: EntityID)?
    /// Each tile's frame in the grid, read only to aim the tile that leaves at the one that stays.
    @State private var tileFrames: [EntityID: CGRect] = [:]
    private static let gridSpace = "people.grid.space"

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = viewModel.notice {
                PersonMoveNoticeSlot(notice: notice) { viewModel.undoMerge() }
            }
        }
        .animation(.default, value: viewModel.notice?.text)
        .sheet(isPresented: $askingSamePerson, onDismiss: samePersonClosed) {
            if let merge = viewModel.merge {
                PersonMergeSheet(viewModel: merge, leaving: nil, picker: false) { receipt in
                    merged = receipt
                    askingSamePerson = false
                }
            }
        }
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
                    ForEach(people) { tile($0) }
                }
                .coordinateSpace(.named(Self.gridSpace))
                .padding(.horizontal, 16).padding(.vertical, 12)
                .accessibilityIdentifier("people.grid")
                errorLine
            }
        }
    }

    /// A tile that can be dragged onto another, and take a drop. The list at the largest text sizes has neither: there
    /// the button on the person's page merges.
    private func tile(_ summary: EntitySummary) -> some View {
        let leaves = vanishing?.leaving == summary.id
        return PersonTile(summary: summary, cover: viewModel.covers[summary.id], deps: viewModel.deps,
                          isDropTarget: dropTarget == summary.id) { viewModel.refresh() }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.gridSpace)) } action: { tileFrames[summary.id] = $0 }
            .scaleEffect(leaves && !reduceMotion ? 0.2 : 1)
            .offset(leaves && !reduceMotion ? offsetToStaying(from: summary.id) : .zero)
            .opacity(leaves ? 0 : 1)
            .zIndex(leaves ? 1 : 0)
            .personDragAndDrop(PersonID(rawValue: summary.id.rawValue)) { dragged in
                dropTarget = nil
                askingSamePerson = viewModel.askMerge(EntityID(rawValue: dragged.rawValue), into: summary.id)
                return true
            } isTargeted: { over in
                if over { dropTarget = summary.id } else if dropTarget == summary.id { dropTarget = nil }
            }
    }

    /// From the centre of the tile that leaves to the centre of the one that stays. Zero when either frame is unknown.
    private func offsetToStaying(from leaving: EntityID) -> CGSize {
        guard let staying = vanishing?.staying, let from = tileFrames[leaving], let to = tileFrames[staying] else { return .zero }
        return CGSize(width: to.midX - from.midX, height: to.midY - from.midY)
    }

    /// The confirm closed: after "Merge" the motion runs; after a refusal the slot says why; after "Cancel" nothing.
    private func samePersonClosed() {
        guard let receipt = merged else { viewModel.mergeRefused(); return }
        merged = nil
        vanish(receipt)
    }

    /// After "Merge": the tile that left shrinks into the one that stays and fades (with Reduce Motion it only fades),
    /// then the grid reads again and the notice offers Undo. The merge is already written; the motion only shows it.
    private func vanish(_ receipt: PersonMergeReceipt) {
        let pair = (leaving: EntityID(rawValue: receipt.leaving.rawValue), staying: EntityID(rawValue: receipt.staying.rawValue))
        withAnimation(.easeIn(duration: 0.25)) {
            vanishing = pair
        } completion: {
            viewModel.merged(receipt)
            vanishing = nil
        }
    }

    private func list(_ people: [EntitySummary]) -> some View {
        List {
            sortMenu.listRowBackground(Color.clear)
            ForEach(people) { PersonRow(summary: $0, cover: viewModel.covers[$0.id], deps: viewModel.deps) { viewModel.refresh() } }
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
