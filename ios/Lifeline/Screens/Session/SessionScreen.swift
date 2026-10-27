import LifelineKit
import SwiftUI

/// R2 Listen (default) and R3 Transcript & memories, one segmented control apart. Below them
/// the offers of the moment (a disclosure card, the wrap-up, the next question), then Pause and
/// Finish. Nothing about time appears for a quick story.
struct SessionScreen: View {
    @Bindable var viewModel: SessionViewModel
    let onEnded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("View", selection: $viewModel.view) {
                Text("Listen").tag(SessionViewModel.ViewMode.listen)
                Text("Transcript & memories").tag(SessionViewModel.ViewMode.review)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .accessibilityIdentifier("session.view")
            switch viewModel.view {
            case .listen: listenView
            case .review: reviewView
            }
            offers
            footer
        }
        .linenBackground()
        .interactiveDismissDisabled()
        .onChange(of: viewModel.landed) { if viewModel.landed { onEnded() } }
        .sheet(item: $viewModel.changing) { memory in
            ChangeSheet(memory: memory, deps: viewModel.deps) {}
        }
    }

    private var header: some View {
        HStack {
            Text("You chose \(viewModel.kindText)")
                .font(.caption)
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier("session.kind")
            Spacer()
            if let line = viewModel.statusLine {
                Text(line).font(.subheadline).foregroundStyle(Theme.ochre)
                    .accessibilityIdentifier("session.status")
            }
            ListeningIndicator(mode: indicatorMode)
                .padding(.leading, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var hasText: Bool {
        !viewModel.state.segments.isEmpty || !viewModel.state.spoken.isEmpty || !viewModel.state.partial.isEmpty
    }

    private var indicatorMode: ListeningIndicator.Mode {
        if viewModel.state.isInterrupted || viewModel.isPaused || viewModel.recorderNotStarted { return .paused }
        return viewModel.state.isSpeaking ? .speaking : .quiet
    }

    // MARK: - Listen (R2)

    private var listenView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                promptCard(compact: false, chips: hasText)
                if let turn = viewModel.latestTurn {
                    TurnLine(turn: turn, font: .system(.headline, design: .serif), identifier: "session.turn")
                }
                Text("Take your time. Pauses are fine. I'm only listening.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Theme.stone)
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isPaused ? "pause.circle" : "record.circle")
                        .foregroundStyle(viewModel.isPaused ? Theme.stone : Theme.ochre)
                    Text(viewModel.isPaused ? "Paused. Nothing is lost." : "Recording, saved as you go")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session.recording")
                Text(viewModel.countText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.olive)
                    .accessibilityIdentifier("session.count")
                Text("The screen can lock. Recording keeps going.")
                    .font(.caption)
                    .foregroundStyle(Theme.stone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    // MARK: - Transcript & memories (R3)

    private var reviewView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    promptCard(compact: hasText)
                    ForEach(viewModel.transcript) { item in
                        switch item {
                        case .segment(let segment):
                            Text(segment.text)
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Theme.ink)
                                .accessibilityIdentifier("session.segment")
                                .id(segment.id)
                        case .turn(let turn):
                            TurnLine(turn: turn, identifier: "transcript.turn")
                        }
                    }
                    liveText
                    CardStack(cards: viewModel.visibleCards, handler: viewModel.cards,
                              onAccept: { viewModel.accept($0) }, onChange: { viewModel.change($0) }, onDismiss: { viewModel.dismiss($0) },
                              onResolve: { viewModel.resolve($0, $1) }, onUndo: { viewModel.undo() },
                              onSameStory: { viewModel.sameStory($0, into: $1) }, onUndoMerge: { viewModel.undoMerge() },
                              onKeepEntity: { viewModel.keepEntity($0, as: $1) })
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .onChange(of: viewModel.state.segments.count) {
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
            .onChange(of: viewModel.visibleCards.map(\.id)) {
                if let last = viewModel.visibleCards.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    /// The prompt stays on screen so the person can think about what to say next. In the review
    /// view it shrinks once words arrive, leaving room for the transcript.
    private func promptCard(compact: Bool, chips: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact {
                Text(viewModel.prompt)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("session.prompt")
            } else {
                Text(viewModel.prompt).titleStyle().accessibilityIdentifier("session.prompt")
                if chips {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(viewModel.alternates.enumerated()), id: \.offset) { index, text in
                            Button { viewModel.swapIn(alternate: index) } label: {
                                Text(text).font(.caption).lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Theme.sand))
                                    .foregroundStyle(Theme.ink)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("session.alternate")
                        }
                    }
                } else {
                    ForEach(Array(viewModel.alternates.enumerated()), id: \.offset) { index, text in
                        Button { viewModel.swapIn(alternate: index) } label: {
                            Text(text).font(.footnote).foregroundStyle(Theme.stone).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("session.alternate")
                    }
                }
            }
        }
        .animation(.default, value: compact)
        .animation(.default, value: chips)
    }

    /// Final words waiting for their segment, then the utterance in progress. Nothing vanishes
    /// between a final and the pause that closes the segment.
    @ViewBuilder
    private var liveText: some View {
        let state = viewModel.state
        if !state.spoken.isEmpty || !state.partial.isEmpty {
            (Text(state.spoken).foregroundStyle(Theme.ink)
                + Text(state.spoken.isEmpty || state.partial.isEmpty ? "" : " ")
                + Text(state.partial).foregroundStyle(Theme.stone))
                .font(.system(.title3, design: .serif))
                .accessibilityIdentifier("session.live")
                .id("live")
        } else {
            Color.clear.frame(height: 1).id("live")
        }
    }

    // MARK: - Offers of the moment

    @ViewBuilder
    private var offers: some View {
        VStack(spacing: 12) {
            if let disclosure = viewModel.disclosure {
                DisclosureCard(text: disclosure, crisisLine: viewModel.crisisLine) { viewModel.dismissDisclosure() }
            }
            if viewModel.wrapUpOffered {
                WrapUpBanner(onFinish: { Task { await viewModel.finish() } }, onKeepGoing: { viewModel.keepGoing() })
            }
            if let next = viewModel.nextPrompt {
                NextPromptOffer(text: next.text, onTake: { viewModel.takeNextPrompt() }, onLater: { viewModel.declineNextPrompt() })
            }
        }
        .padding(.horizontal, 24)
        .animation(.default, value: viewModel.wrapUpOffered)
        .animation(.default, value: viewModel.nextPrompt?.logID)
        .animation(.default, value: viewModel.disclosure)
    }

    @ViewBuilder
    private var footer: some View {
        if let startError = viewModel.startError {
            VStack(spacing: 12) {
                Text(startError).foregroundStyle(.red).accessibilityIdentifier("session.startError")
                Button("Close") { onEnded() }.accessibilityIdentifier("session.close")
            }
            .padding(24)
        } else {
            HStack(spacing: 12) {
                Button {
                    Task { if viewModel.isPaused { await viewModel.resume() } else { await viewModel.pause() } }
                } label: {
                    Label(viewModel.isPaused ? "Resume" : "Pause", systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand))
                        .foregroundStyle(Theme.ink)
                }
                .disabled(viewModel.isStopping || viewModel.recorderNotStarted)
                .accessibilityIdentifier("session.pause")
                Button {
                    Task { await viewModel.finish() }
                } label: {
                    Text(viewModel.isStopping ? "Finishing…" : "Finish")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.olive))
                        .foregroundStyle(.white)
                }
                .disabled(viewModel.isStopping || viewModel.recorderNotStarted)
                .accessibilityIdentifier("session.finish")
            }
            .padding(24)
        }
    }
}
