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
                         delete: { viewModel.deleteTarget = $0 })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section {
                        Text(viewModel.summary).font(.subheadline).foregroundStyle(Theme.stone)
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("timeline.summary")
                    }
                    if !viewModel.waiting.isEmpty {
                        Section("Waiting for you") {
                            CardStack(cards: viewModel.waiting, handler: viewModel.cards,
                                      onAccept: { viewModel.accept($0) }, onChange: { viewModel.change($0) }, onDismiss: { viewModel.dismiss($0) },
                                      onResolve: { viewModel.resolve($0, $1) }, onUndo: { viewModel.undo() },
                              onSameStory: { viewModel.sameStory($0, into: $1) })
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .accessibilityIdentifier("timeline.waiting")
                        }
                    }
                    ForEach(viewModel.chapters) { chapter in
                        ChapterSection(title: chapter.title, rangeText: chapter.chapter.range.isPlaced ? chapter.chapter.range.displayText : nil,
                                       memories: chapter.memories, axis: viewModel.axis, actions: rowActions)
                    }
                    if !viewModel.unchaptered.isEmpty {
                        ChapterSection(title: viewModel.chapters.isEmpty ? "On the timeline" : "Outside any chapter", rangeText: nil,
                                       memories: viewModel.unchaptered, axis: viewModel.axis, actions: rowActions)
                    }
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
                    if !viewModel.shelf.isEmpty {
                        ShelfSection(title: "Somewhere in your story", memories: viewModel.shelf, actions: rowActions)
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
                    if viewModel.memoryCount == 0 && viewModel.waiting.isEmpty {
                        ContentUnavailableView("Your story so far", systemImage: "book.closed",
                                               description: Text("Tap Start and tell me about the house you grew up in."))
                            .listRowBackground(Color.clear)
                    }
                    if let error = viewModel.error ?? viewModel.cards.error ?? viewModel.home.error {
                        Text(error).foregroundStyle(.red)
                    }
                    Color.clear.frame(height: 120).listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)

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
            .linenBackground()
            .navigationTitle("Your story so far")
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
                SettingsScreen(deps: viewModel.deps)
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
}
