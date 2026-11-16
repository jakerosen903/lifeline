import LifelineKit
import SwiftUI

/// Your story so far. The Timeline tab's root: waiting cards, the spine of dated moments,
/// collections, the shelf and the one open question. Facts, feelings and goals live on You.
struct TimelineScreen: View {
    let viewModel: TimelineViewModel
    @State private var showSettings = false
    @State private var openMemory: MemoryRow?
    @State private var collectionTarget: MemoryRow?
    @State private var dateTarget: MemoryRow?
    @State private var collectionTitle = ""
    @State private var renameTarget: StoryRow?
    @State private var storyTitle = ""
    @State private var splitTarget: StoryRow?
    @State private var moveTarget: MemoryRow?

    private var rowActions: MemoryRowActions {
        MemoryRowActions(open: { openMemory = $0 },
                         addToCollection: { collectionTarget = $0 },
                         addDate: { dateTarget = $0 },
                         hide: { viewModel.hide($0.id) },
                         setExcluded: { viewModel.setExcluded($0.id, $1) },
                         delete: { viewModel.deleteTarget = $0 },
                         moveToStory: { moveTarget = $0 },
                         takeOutOfStory: { viewModel.takeOutOfStory($0.id) })
    }

    private var storyActions: StoryRowActions {
        StoryRowActions(rename: { storyTitle = $0.story.title ?? ""; renameTarget = $0 }, split: { splitTarget = $0 })
    }

    var body: some View {
        timelineList
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle("Your story so far")
            .storyDialogs(rename: $renameTarget, title: $storyTitle, split: $splitTarget, move: $moveTarget, viewModel: viewModel)
            .navigationDestination(item: Binding(get: { viewModel.openedEntity }, set: { viewModel.openedEntity = $0 })) { entity in
                EntityScreen(viewModel: EntityViewModel(entity: entity, deps: viewModel.deps)) { viewModel.refresh() }
            }
            .navigationDestination(item: $openMemory) { row in
                MemoryScreen(viewModel: MemoryViewModel(memory: row.memory, deps: viewModel.deps), deps: viewModel.deps) { viewModel.refresh() }
            }
            .toolbar {
                NavigationLink("Sessions") { SessionsScreen(viewModel: viewModel.home) }
                    .accessibilityIdentifier("timeline.sessions")
                Menu {
                    Toggle("Show hidden memories", isOn: Binding(get: { viewModel.showHidden }, set: { viewModel.showHidden = $0 }))
                        .accessibilityIdentifier("timeline.showHidden")
                    if !viewModel.allTags.isEmpty {
                        Menu {
                            Button("Everything") { viewModel.tagFilter = nil }
                            ForEach(viewModel.allTags, id: \.self) { tag in
                                Button { viewModel.tagFilter = tag } label: {
                                    if viewModel.tagFilter == tag { Label(tag, systemImage: "checkmark") } else { Text(tag) }
                                }
                            }
                        } label: { Label(viewModel.tagFilter.map { "Showing \($0)" } ?? "Filter by tag", systemImage: viewModel.tagFilter == nil ? "tag" : "tag.fill") }
                            .accessibilityIdentifier("timeline.tagFilter")
                    }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("timeline.more")
            }
            .sheet(isPresented: $showSettings, onDismiss: { viewModel.refresh() }) {
                SettingsScreen(deps: viewModel.deps, isSessionLive: { viewModel.home.presented != nil })
            }
            .sheet(item: Binding(get: { viewModel.changing }, set: { viewModel.changing = $0 })) { memory in
                ChangeSheet(memory: memory, deps: viewModel.deps, includeHidden: viewModel.showHidden) { viewModel.refresh() }
            }
            .sheet(item: $dateTarget, onDismiss: { viewModel.refresh() }) { row in
                TellMeWhenSheet(title: row.memory.title, birthDate: try? viewModel.deps.extractionStore.profile.ownerBirthDate()) { viewModel.setStated(row.id, $0) }
            }
            .confirmationDialog("Delete this memory?", isPresented: Binding(get: { viewModel.deleteTarget != nil }, set: { if !$0 { viewModel.deleteTarget = nil } }),
                                titleVisibility: .visible, presenting: viewModel.deleteTarget) { row in
                Button("Delete “\(row.memory.title)”", role: .destructive) { viewModel.delete(row.id); viewModel.deleteTarget = nil }
                    .accessibilityIdentifier("row.confirmDelete")
                Button("Cancel", role: .cancel) { viewModel.deleteTarget = nil }
            } message: { _ in
                Text("The memory, its people and its dates go. Your recording stays in Sessions.")
            }
            .alert("Add to a collection", isPresented: Binding(get: { collectionTarget != nil }, set: { if !$0 { collectionTarget = nil } }), presenting: collectionTarget) { row in
                TextField("Collection name", text: $collectionTitle)
                Button("Add") {
                    viewModel.addToCollection(row.id, title: collectionTitle)
                    collectionTitle = ""
                    collectionTarget = nil
                }
                .disabled(collectionTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { collectionTarget = nil }
            } message: { _ in
                Text(viewModel.existingCollectionTitles.isEmpty ? "In your own words." : "Existing: " + viewModel.existingCollectionTitles.joined(separator: ", "))
            }
            .onAppear { viewModel.refresh() }
    }

    private var timelineList: some View {
        List {
            summarySection
            sortingRow
            waitingSection
            spineSection
            collectionSections
            shelfAndQuestion
            footer
        }
    }

    @ViewBuilder private var sortingRow: some View {
        if viewModel.sortingLine != nil {
            SortingLine(status: viewModel.sorting, onOpenSettings: { showSettings = true }, onTryAgain: { viewModel.tryAgain() })
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var summarySection: some View {
        Section {
            Text(viewModel.summary).font(.subheadline).foregroundStyle(Theme.secondaryText)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("timeline.summary")
        }
    }

    @ViewBuilder private var waitingSection: some View {
        if !viewModel.waiting.isEmpty || !viewModel.pairs.isEmpty {
            Section {
                CardStack(cards: viewModel.waiting, handler: viewModel.cards,
                          onAccept: { viewModel.accept($0) }, onChange: { viewModel.change($0) }, onDismiss: { viewModel.dismiss($0) },
                          onResolve: { viewModel.resolve($0, $1) }, onUndo: { viewModel.undo() },
                          onSameStory: { viewModel.sameStory($0, into: $1) }, onUndoMerge: { viewModel.undoMerge() }, onUndoKeptClose: { viewModel.undoKeptClose() },
                          pairs: viewModel.pairs, onPair: { viewModel.answerPair($0, same: $1) }, onUndoPair: { viewModel.undoPair() },
                          onFollowUp: { viewModel.followUp($0, $1, as: $2) },
                          onResolveFollowUp: { viewModel.resolveFollowUp($0, $1, $2) },
                          onDeclineFollowUp: { viewModel.declineFollowUp($0, $1) },
                          onKeptDone: { viewModel.keptDone($0) },
                          onOpenEntity: { viewModel.open($0) }, hasPage: { viewModel.flow.hasPage($0) })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } header: {
                // The List lays the stack out as rows; an identifier on the stack would replace every card's own.
                Text("Waiting for you").accessibilityIdentifier("timeline.waiting")
            }
        }
    }

    /// One section of rows with no header, cards or separators: the rows touch, so the spine reads as one line.
    /// With nothing dated there is no section, and so no spine and no period.
    @ViewBuilder private var spineSection: some View {
        if !viewModel.spine.isEmpty {
            Section {
                ForEach(viewModel.spine) { row in
                    SpineRowView(row: row, isFirst: row.id == viewModel.spine.first?.id, isLast: row.id == viewModel.spine.last?.id,
                                 expanded: storyID(of: row).map { viewModel.expandedStories.contains($0) } ?? false,
                                 onToggleStory: { storyID(of: row).map { viewModel.toggleStory($0) } },
                                 actions: rowActions, storyActions: storyActions)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
            }
        }
    }

    private func storyID(of row: SpineRow) -> StoryID? {
        if case .story(let story) = row.content { story.id } else { nil }
    }

    @ViewBuilder private var collectionSections: some View {
        ForEach(viewModel.collections) { collection in
            Section {
                ForEach(collection.members) { row in
                    MemoryRowView(row: row, actions: rowActions)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Collection").font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(collection.collection.title).font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink).textCase(nil)
                    Text(collection.span.isPlaced ? collection.span.displayText : "no dates yet").font(.caption).foregroundStyle(Theme.ochreText)
                }
                .accessibilityIdentifier("timeline.collection")
            }
        }
    }

    @ViewBuilder private var shelfAndQuestion: some View {
        if !viewModel.shelf.isEmpty || !viewModel.shelfStories.isEmpty {
            ShelfSection(title: "Somewhere in your story", memories: viewModel.shelf, actions: rowActions,
                         stories: viewModel.shelfStories, expanded: viewModel.expandedStories, onToggleStory: { viewModel.toggleStory($0) },
                         storyActions: storyActions)
        }
        if let question = viewModel.question, let row = viewModel.questionRow {
            Section {
                RefineCard(title: row.memory.title, bestGuess: row.rangeText, question: question,
                           onChoose: { viewModel.answer($0) }, onKeep: { viewModel.keepForNow() })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } header: {
                let n = viewModel.shelf.count + viewModel.floatingCount
                Text("\(n) \(n == 1 ? "memory" : "memories") waiting for a place").font(.caption).foregroundStyle(Theme.secondaryText).textCase(nil)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if viewModel.memoryCount == 0 && viewModel.waiting.isEmpty {
            ContentUnavailableView("Your story so far", systemImage: "book.closed",
                                   description: Text("Tap “Tell a story” and tell me about the house you grew up in."))
                .listRowBackground(Color.clear)
        }
        // A start error shows on the record bar instead, under the same identifier.
        if let error = viewModel.error ?? viewModel.cards.error ?? viewModel.home.error {
            Text(error).foregroundStyle(.red).accessibilityIdentifier("timeline.error")
        }
    }
}

/// The story dialogs (M5), kept off the main body so the type-checker stays quick.
private struct StoryDialogs: ViewModifier {
    @Binding var renameTarget: StoryRow?
    @Binding var storyTitle: String
    @Binding var splitTarget: StoryRow?
    @Binding var moveTarget: MemoryRow?
    let viewModel: TimelineViewModel

    func body(content: Content) -> some View {
        content
    .alert("Rename this story", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }), presenting: renameTarget) { row in
        TextField("Story title", text: $storyTitle)
        Button("Rename") {
            viewModel.renameStory(row.id, title: storyTitle)
            renameTarget = nil
        }
        .disabled(storyTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Cancel", role: .cancel) { renameTarget = nil }
    } message: { _ in
        Text("In your own words.")
    }
    .sheet(item: $splitTarget, onDismiss: { viewModel.refresh() }) { row in
        SplitStorySheet(row: row) { viewModel.splitStory(row.id, taking: $0) }
    }
    .sheet(item: $moveTarget, onDismiss: { viewModel.refresh() }) { row in
        MoveToStorySheet(stories: viewModel.otherStories(for: row)) { viewModel.moveToStory(row.id, story: $0) }
    }
    }
}

private extension View {
    func storyDialogs(rename: Binding<StoryRow?>, title: Binding<String>, split: Binding<StoryRow?>, move: Binding<MemoryRow?>, viewModel: TimelineViewModel) -> some View {
        modifier(StoryDialogs(renameTarget: rename, storyTitle: title, splitTarget: split, moveTarget: move, viewModel: viewModel))
    }
}
