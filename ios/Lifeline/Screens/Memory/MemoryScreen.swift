import LifelineKit
import SwiftUI

/// The Event canvas: when, the title, where and with whom, the owner's voice and words, the
/// people in it, and the evidence behind the range. Tapping the range opens the refine card.
struct MemoryScreen: View {
    let viewModel: MemoryViewModel
    let deps: Dependencies
    let onChange: () -> Void
    @State private var refining = false
    @State private var tellingWhen = false
    @Environment(\.dismiss) private var dismiss
    @State private var changing = false
    @State private var whoIsThis: Mention?

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

                if !viewModel.checkThis.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.checkThis, id: \.label) { tag in
                            Button {
                                if let mention = viewModel.mention(for: tag) { whoIsThis = mention } else { refining = true }
                            } label: { CheckThisTag(tag: tag) }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if viewModel.place != nil || !viewModel.people.isEmpty {
                    Text([viewModel.place?.nameText, viewModel.people.isEmpty ? nil : "with " + viewModel.people.map(\.displayName).joined(separator: " and ")]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Theme.stone)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("In your voice").font(.caption.weight(.semibold)).foregroundStyle(Theme.olive)
                    // Every telling, first first; a retelling shows the words it was kept under (M4.1).
                    ForEach(viewModel.spans, id: \.span.order) { telling in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button { viewModel.togglePlayback(of: telling.span) } label: {
                                    Label(viewModel.isPlaying(telling.span) ? "Stop" : "Play",
                                          systemImage: viewModel.isPlaying(telling.span) ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.title3)
                                }
                                .tint(Theme.olive)
                                .accessibilityIdentifier("memory.play")
                                Spacer()
                                Text("recorded " + telling.session.startedAt.formatted(.dateTime.month().day().year())).font(.caption).foregroundStyle(Theme.stone)
                                if telling.span.order > 0 {
                                    Menu {
                                        Button("Separate this telling", systemImage: "arrow.triangle.branch") { viewModel.separate(order: telling.span.order); onChange() }
                                            .accessibilityIdentifier("telling.separate")
                                    } label: {
                                        Image(systemName: "ellipsis.circle").foregroundStyle(Theme.stone)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("telling.more")
                                }
                            }
                            if telling.span.order == 0 {
                                Text("“\(viewModel.memory.summaryQuote)”")
                                    .font(.system(.body, design: .serif))
                                    .foregroundStyle(Theme.ink)
                            } else if let title = telling.span.titleText {
                                Text("also told as: “\(title)”")
                                    .font(.system(.body, design: .serif))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("memory.span")
                    }
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
        .toolbar {
            Button("Change…") { changing = true }.accessibilityIdentifier("memory.change")
        }
        .sheet(isPresented: $changing, onDismiss: { viewModel.refresh(); onChange() }) {
            ChangeSheet(memory: viewModel.memory, deps: deps) {}
        }
        .sheet(item: $whoIsThis, onDismiss: { viewModel.refresh(); onChange() }) { mention in
            let handler = CardHandler(deps: deps)
            let card = Card(mention)
            WhoIsThisCard(text: mention.text, people: handler.peopleChoices(for: mention.text)) { choice in
                if handler.resolve(card, choice) { whoIsThis = nil }
            }
            .padding(24)
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.linen)
        }
        .sheet(isPresented: $refining, onDismiss: { viewModel.refresh(); onChange(); if tellingWhen { } }) {
            RefineCard(title: viewModel.memory.title, bestGuess: viewModel.rangeText, question: viewModel.question,
                       onChoose: { viewModel.answer($0); refining = false }, onKeep: { refining = false },
                       onTellMeWhen: { refining = false; tellingWhen = true })
                .padding(24)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.linen)
        }
        .sheet(isPresented: $tellingWhen, onDismiss: { viewModel.refresh(); onChange() }) {
            TellMeWhenSheet(title: viewModel.memory.title, birthDate: viewModel.birthDate) { viewModel.setStated($0) }
        }
        .onChange(of: viewModel.isGone) { if viewModel.isGone { onChange(); dismiss() } }
        .onDisappear { viewModel.stop() }
    }
}
