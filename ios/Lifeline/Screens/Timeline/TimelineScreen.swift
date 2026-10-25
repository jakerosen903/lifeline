import LifelineKit
import SwiftUI

/// Your story so far. The home screen: waiting cards, chapters with bands, collections, the
/// shelf, the one open question, and Start.
struct TimelineScreen: View {
    let viewModel: TimelineViewModel
    @Bindable private var home: HomeViewModel
    @State private var showSettings = false
    @State private var openMemory: MemoryRow?
    @State private var collectionTarget: MemoryRow?
    @State private var dateTarget: MemoryRow?
    @State private var collectionTitle = ""
    @State private var renameTarget: StoryRow?
    @State private var storyTitle = ""
    @State private var splitTarget: StoryRow?
    @State private var moveTarget: MemoryRow?

    init(viewModel: TimelineViewModel) {
        self.viewModel = viewModel
        _home = Bindable(viewModel.home)
    }

    private var rowActions: MemoryRowActions {
        MemoryRowActions(open: { openMemory = $0 },
                         newChapter: { viewModel.newChapter(for: $0.id, title: nil) },
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
        NavigationStack {
            ZStack(alignment: .bottom) {
                timelineList
                .scrollContentBackground(.hidden)

                startButtons
            }
            .linenBackground()
            .navigationTitle("Your story so far")
            .storyDialogs(rename: $renameTarget, title: $storyTitle, split: $splitTarget, move: $moveTarget, viewModel: viewModel)
            .navigationDestination(item: $openMemory) { row in
                MemoryScreen(viewModel: MemoryViewModel(memory: row.memory, deps: viewModel.deps), deps: viewModel.deps) { viewModel.refresh() }
            }
            .toolbar {
                Button { viewModel.showHidden.toggle() } label: { Image(systemName: viewModel.showHidden ? "eye" : "eye.slash") }
                    .accessibilityLabel(viewModel.showHidden ? "Showing hidden memories" : "Hidden memories are not shown")
                    .accessibilityIdentifier("timeline.showHidden")
                NavigationLink { SessionsScreen(viewModel: viewModel.home) } label: { Image(systemName: "waveform") }
                    .accessibilityIdentifier("timeline.sessions")
                NavigationLink { PeopleScreen(viewModel: PeopleViewModel(deps: viewModel.deps)) } label: { Image(systemName: "person.2") }
                    .accessibilityIdentifier("home.people")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityIdentifier("home.settings")
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
            .fullScreenCover(item: $home.presented) { presented in
                switch presented {
                case .session(let session):
                    SessionScreen(viewModel: session) { viewModel.sessionEnded() }
                case .landing(let landing):
                    LandingScreen(viewModel: landing) { another in viewModel.home.landingClosed(tellAnother: another); viewModel.refresh() }
                }
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
    }

    private var timelineList: some View {
        List {
            summarySection
            sortingRow
            waitingSection
            chapterSections
            collectionSections
            shelfAndQuestion
            if !viewModel.about.isEmpty { AboutSection(rows: viewModel.about, actions: rowActions) }
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
            Text(viewModel.summary).font(.subheadline).foregroundStyle(Theme.stone)
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
                          onSameStory: { viewModel.sameStory($0, into: $1) }, onUndoMerge: { viewModel.undoMerge() },
                          pairs: viewModel.pairs, onPair: { viewModel.answerPair($0, same: $1) }, onUndoPair: { viewModel.undoPair() },
                          onKeepEntity: { viewModel.keepEntity($0, as: $1) })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } header: {
                // The List lays the stack out as rows; an identifier on the stack would replace every card's own.
                Text("Waiting for you").accessibilityIdentifier("timeline.waiting")
            }
        }
    }

    @ViewBuilder private var chapterSections: some View {
        ForEach(viewModel.chapters) { chapter in
            ChapterSection(title: chapter.title, rangeText: chapter.chapter.range.isPlaced ? chapter.chapter.range.displayText : nil,
                           memories: chapter.memories, axis: viewModel.axis, actions: rowActions,
                           stories: chapter.stories, expanded: viewModel.expandedStories, onToggleStory: { viewModel.toggleStory($0) },
                           storyActions: storyActions)
        }
        if !viewModel.unchaptered.isEmpty || !viewModel.unchapteredStories.isEmpty {
            ChapterSection(title: viewModel.chapters.isEmpty ? "On the timeline" : "Outside any chapter", rangeText: nil,
                           memories: viewModel.unchaptered, axis: viewModel.axis, actions: rowActions,
                           stories: viewModel.unchapteredStories, expanded: viewModel.expandedStories, onToggleStory: { viewModel.toggleStory($0) },
                           storyActions: storyActions)
        }
    }

    @ViewBuilder private var collectionSections: some View {
        ForEach(viewModel.collections) { collection in
            Section {
                ForEach(collection.members) { row in
                    MemoryRowView(row: row, axis: row.memory.range.isPlaced ? viewModel.axis : nil, actions: rowActions)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Collection").font(.caption).foregroundStyle(Theme.stone)
                    Text(collection.collection.title).font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink).textCase(nil)
                    Text(collection.span.isPlaced ? collection.span.displayText : "no dates yet").font(.caption).foregroundStyle(Theme.ochre)
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
                Text("\(n) \(n == 1 ? "memory" : "memories") waiting for a place").font(.caption).foregroundStyle(Theme.stone).textCase(nil)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if viewModel.memoryCount == 0 && viewModel.waiting.isEmpty {
            ContentUnavailableView("Your story so far", systemImage: "book.closed",
                                   description: Text("Tap Start and tell me about the house you grew up in."))
                .listRowBackground(Color.clear)
        }
        if let error = viewModel.error ?? viewModel.cards.error ?? viewModel.home.error {
            Text(error).foregroundStyle(.red).accessibilityIdentifier("timeline.error")
        }
        Color.clear.frame(height: 120).listRowBackground(Color.clear)
    
    }

    private var startButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.home.startSession(kind: .quick) }
            } label: {
                Label("Tell a quick story", systemImage: "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.olive))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("home.start")
            Button {
                Task { await viewModel.home.startSession(kind: .settleIn) }
            } label: {
                Text("Settle in")
                    .font(.headline)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityIdentifier("home.settleIn")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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
