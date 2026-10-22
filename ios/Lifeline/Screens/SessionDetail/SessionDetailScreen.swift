import LifelineKit
import SwiftUI

/// Timeline, M1 form: one session's moments, each playable.
struct SessionDetailScreen: View {
    let viewModel: SessionDetailViewModel

    var body: some View {
        List {
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
            if let error = viewModel.error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("detail.error")
            }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle(viewModel.session.startedAt.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.stop() }
    }
}
