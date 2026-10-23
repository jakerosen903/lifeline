import LifelineKit
import SwiftUI

/// Main. The live session: a prompt that stays while the person talks, the growing transcript,
/// a listening indicator, elapsed time, and Stop.
struct SessionScreen: View {
    let viewModel: SessionViewModel
    let onEnded: () -> Void

    private static let prompt = "Tell me about the house you grew up in."
    private static let alternates = ["A meal you can still taste.", "A teacher you remember.", "The first place that felt like yours."]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        promptCard(compact: hasText)
                        ForEach(viewModel.state.segments) { segment in
                            Text(segment.text)
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Theme.ink)
                                .accessibilityIdentifier("session.segment")
                                .id(segment.id)
                        }
                        liveText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .onChange(of: viewModel.state.segments.count) {
                    withAnimation { proxy.scrollTo("live", anchor: .bottom) }
                }
            }
            footer
        }
        .linenBackground()
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack {
            TimelineView(.periodic(from: viewModel.startedAt, by: 1)) { context in
                Text(Format.duration(from: viewModel.startedAt, to: context.date))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("session.elapsed")
            }
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
        if viewModel.state.isInterrupted || viewModel.recorderNotStarted { return .paused }
        return viewModel.state.isSpeaking ? .speaking : .quiet
    }

    /// The prompt stays on screen so the person can think about what to say next. Once words
    /// arrive it shrinks and the alternates go, leaving room for the transcript.
    private func promptCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact {
                Text(Self.prompt)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("session.prompt")
            } else {
                Text(Self.prompt).titleStyle().accessibilityIdentifier("session.prompt")
                ForEach(Self.alternates, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.stone) }
            }
        }
        .animation(.default, value: compact)
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

    @ViewBuilder
    private var footer: some View {
        if let startError = viewModel.startError {
            VStack(spacing: 12) {
                Text(startError).foregroundStyle(.red).accessibilityIdentifier("session.startError")
                Button("Close") { onEnded() }.accessibilityIdentifier("session.close")
            }
            .padding(24)
        } else {
            stopButton
        }
    }

    private var stopButton: some View {
        Button {
            Task {
                await viewModel.stop()
                onEnded()
            }
        } label: {
            Text(viewModel.isStopping ? "Finishing…" : "Stop")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand))
                .foregroundStyle(Theme.ink)
        }
        .disabled(viewModel.isStopping || viewModel.recorderNotStarted)
        .accessibilityIdentifier("session.stop")
        .padding(24)
    }
}
