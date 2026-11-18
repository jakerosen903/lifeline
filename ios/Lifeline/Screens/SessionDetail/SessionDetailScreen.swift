import LifelineKit
import SwiftUI

/// One session: cards still waiting for an answer, the memories it produced, and every
/// moment, each playable. The timeline proper is M3.
struct SessionDetailScreen: View {
    /// Made once per navigation: a parent that re-renders (the landing polls while sorting) must
    /// not swap the model, and with it the cards' touched state, under the person.
    @State private var viewModel: SessionDetailViewModel

    init(session: Session, deps: Dependencies) {
        _viewModel = State(initialValue: SessionDetailViewModel(session: session, deps: deps))
    }

    var body: some View {
        List {
            if !viewModel.waiting.isEmpty {
                Section("Waiting for you") {
                    CardStack(cards: viewModel.waiting, handler: viewModel.cards,
                              onAccept: { viewModel.accept($0) }, onChange: { viewModel.change($0) }, onDismiss: { viewModel.dismiss($0) },
                              onResolve: { viewModel.resolve($0, $1) }, onUndo: { viewModel.undo() },
                              onSameStory: { viewModel.sameStory($0, into: $1) }, onUndoMerge: { viewModel.undoMerge() }, onUndoKeptClose: { viewModel.undoKeptClose() },
                              onFollowUp: { viewModel.followUp($0, $1, as: $2) },
                              onResolveFollowUp: { viewModel.resolveFollowUp($0, $1, $2) },
                              onDeclineFollowUp: { viewModel.declineFollowUp($0, $1) },
                              onKeptDone: { viewModel.keptDone($0) },
                              onOpenEntity: { viewModel.open($0) }, hasPage: { viewModel.flow.hasPage($0) })
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            if !viewModel.memories.isEmpty {
                Section("Memories") {
                    ForEach(viewModel.memories) { row in
                        NavigationLink {
                            MemoryScreen(viewModel: MemoryViewModel(memory: row.memory, deps: viewModel.deps), deps: viewModel.deps) { viewModel.refresh() }
                        } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if row.kind != .event && row.kind != .other {
                                Text(row.kind.cardLabel).font(.caption2.weight(.semibold)).foregroundStyle(Theme.oliveText)
                            }
                            Text(row.memory.title)
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(Theme.ink)
                            Text("“\(row.memory.summaryQuote)”")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(3)
                            if !row.anchors.isEmpty {
                                Text(row.anchors.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.ochreText)
                            }
                            if !row.people.isEmpty {
                                Text(row.people.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.oliveText)
                            }
                        }
                        .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("detail.memory")
                    }
                }
            }
            Section(viewModel.memories.isEmpty && viewModel.waiting.isEmpty ? "" : "Moments") {
                if viewModel.segments.isEmpty {
                    ContentUnavailableView("Nothing was said", systemImage: "waveform.slash",
                                           description: Text("This session has no transcribed moments."))
                        .listRowBackground(Color.clear)
                }
                ForEach(viewModel.transcript) { item in
                    switch item {
                    case .segment(let segment): segmentRow(segment)
                    case .turn(let turn): TurnLine(turn: turn, identifier: "transcript.turn").padding(.leading, 40)
                    }
                }
            }
            if !viewModel.dismissed.isEmpty {
                Section("Dismissed") {
                    ForEach(viewModel.dismissed) { candidate in
                        HStack {
                            Text(CandidatePayload.memory(candidate)?.title ?? CandidatePayload.mention(candidate)?.text ?? "")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Button("Bring back") { viewModel.bringBack(candidate) }
                                .buttonStyle(.bordered)
                                .tint(Theme.oliveOnFill)
                                .accessibilityIdentifier("detail.bringBack")
                        }
                    }
                }
            }
            if let error = viewModel.error ?? viewModel.cards.error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("detail.error")
            }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle(viewModel.session.startedAt.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refresh() }
        .onDisappear { viewModel.stop() }
        .navigationDestination(item: Binding(get: { viewModel.openedEntity }, set: { viewModel.openedEntity = $0 })) { entity in
            EntityScreen(viewModel: EntityViewModel(entity: entity, deps: viewModel.deps)) { viewModel.refresh() }
        }
        .sheet(item: Binding(get: { viewModel.changing }, set: { viewModel.changing = $0 }), onDismiss: { viewModel.cards.peopleChanged() }) { memory in
            ChangeSheet(memory: memory, deps: viewModel.deps) { viewModel.refresh() }
        }
    }

    /// Tap plays the moment's own span.
    private func segmentRow(_ segment: Segment) -> some View {
        Button { viewModel.toggle(segment) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: viewModel.isPlaying(segment) ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.olive)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.duration(ms: segment.startMs))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.ochreText)
                    Text(segment.text)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("detail.segment")
    }
}
