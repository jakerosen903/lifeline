import LifelineKit
import SwiftUI

/// The Event canvas: when, the title, where and with whom, the owner's voice and words, the
/// people in it, and the evidence behind the range. Tapping the range opens the refine card.
struct MemoryScreen: View {
    let viewModel: MemoryViewModel
    let onChange: () -> Void
    @State private var refining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { refining = true } label: {
                    HStack(spacing: 8) {
                        Text([viewModel.rangeText, viewModel.ageText].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ochre)
                        if let chapter = viewModel.chapterTitle {
                            Text("· \(chapter)").font(.subheadline).foregroundStyle(Theme.stone)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.stone)
                    }
                }
                .accessibilityIdentifier("memory.range")

                Text(viewModel.memory.title).titleStyle()

                if viewModel.place != nil || !viewModel.people.isEmpty {
                    Text([viewModel.place?.nameText, viewModel.people.isEmpty ? nil : "with " + viewModel.people.map(\.displayName).joined(separator: " and ")]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Theme.stone)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("In your voice").font(.caption.weight(.semibold)).foregroundStyle(Theme.olive)
                        Spacer()
                        if let session = viewModel.session {
                            Text("recorded " + session.startedAt.formatted(.dateTime.month().day().year())).font(.caption).foregroundStyle(Theme.stone)
                        }
                    }
                    Button { viewModel.togglePlayback() } label: {
                        Label(viewModel.isPlaying ? "Stop" : "Play", systemImage: viewModel.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title3)
                    }
                    .tint(Theme.olive)
                    .accessibilityIdentifier("memory.play")
                    Text("“\(viewModel.memory.summaryQuote)”")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))

                if !viewModel.people.isEmpty || viewModel.place != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("In this memory").font(.caption.weight(.semibold)).foregroundStyle(Theme.olive)
                        FlowChips(items: viewModel.people.map(\.displayName) + (viewModel.place.map { [$0.nameText] } ?? []))
                    }
                }

                if let evidence = viewModel.evidence {
                    Text("you said: “\(evidence)”")
                        .font(.footnote)
                        .foregroundStyle(Theme.stone)
                        .accessibilityIdentifier("memory.evidence")
                }

                if let error = viewModel.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("memory.error")
                }
            }
            .padding(24)
        }
        .linenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $refining, onDismiss: { viewModel.refresh(); onChange() }) {
            RefineCard(title: viewModel.memory.title, bestGuess: viewModel.rangeText, question: viewModel.question,
                       onChoose: { viewModel.answer($0); refining = false }, onKeep: { refining = false })
                .padding(24)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.linen)
        }
        .onDisappear { viewModel.stop() }
    }
}
