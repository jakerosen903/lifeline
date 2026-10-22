import LifelineKit
import SwiftUI

/// Main. The live session: a prompt, the growing transcript, elapsed time, and Stop.
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
                        if viewModel.state.segments.isEmpty && viewModel.state.partial.isEmpty {
                            promptCard
                        }
                        ForEach(viewModel.state.segments) { segment in
                            Text(segment.text)
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Theme.ink)
                                .accessibilityIdentifier("session.segment")
                                .id(segment.id)
                        }
                        if !viewModel.state.partial.isEmpty {
                            Text(viewModel.state.partial)
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Theme.stone)
                                .id("partial")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .onChange(of: viewModel.state.segments.count) {
                    withAnimation { proxy.scrollTo(viewModel.state.segments.last?.id, anchor: .bottom) }
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
            } else {
                Circle().fill(Theme.olive).frame(width: 10, height: 10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.prompt).titleStyle()
            ForEach(Self.alternates, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.stone) }
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
