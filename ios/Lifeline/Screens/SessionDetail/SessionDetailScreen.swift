import LifelineKit
import SwiftUI

/// One session: cards still waiting for an answer, the memories it produced, and every
/// moment, each playable. The timeline proper is M3.
struct SessionDetailScreen: View {
    let viewModel: SessionDetailViewModel

    var body: some View {
        List {
            if !viewModel.waiting.isEmpty {
                Section("Waiting for you") {
                    CardStack(cards: viewModel.waiting, handler: viewModel.cards,
                              onAccept: { viewModel.accept($0) }, onDismiss: { viewModel.dismiss($0) },
                              onResolve: { viewModel.resolve($0, $1) })
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            if !viewModel.memories.isEmpty {
                Section("Memories") {
                    ForEach(viewModel.memories) { row in
                        NavigationLink {
                            MemoryScreen(viewModel: MemoryViewModel(memory: row.memory, deps: viewModel.deps)) { viewModel.refresh() }
                        } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if row.kind != .event && row.kind != .other {
                                Text(row.kind.cardLabel).font(.caption2.weight(.semibold)).foregroundStyle(Theme.olive)
                            }
                            Text(row.memory.title)
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(Theme.ink)
                            Text("“\(row.memory.summaryQuote)”")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Theme.stone)
                                .lineLimit(3)
                            if !row.anchors.isEmpty {
                                Text(row.anchors.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.ochre)
                            }
                            if !row.people.isEmpty {
                                Text(row.people.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.olive)
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
                ForEach(viewModel.segments) { segment in
                    Button { viewModel.toggle(segment) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: viewModel.isPlaying(segment) ? "stop.circle.fill" : "play.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.olive)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Format.duration(ms: segment.startMs))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.ochre)
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
    }
}
