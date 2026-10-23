import LifelineKit
import SwiftUI

/// Past sessions, newest first. The M1 home list, now one tap from the timeline.
struct SessionsScreen: View {
    let viewModel: HomeViewModel

    var body: some View {
        List {
            if viewModel.rows.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "waveform",
                                       description: Text("Tap Start on the timeline and tell me about the house you grew up in."))
                    .listRowBackground(Color.clear)
            }
            ForEach(viewModel.rows) { row in
                NavigationLink {
                    SessionDetailScreen(viewModel: SessionDetailViewModel(session: row.session, deps: viewModel.deps))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.session.startedAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                            .font(.system(.headline, design: .serif))
                        Text("\(row.durationText) · \(row.segmentCount) moments")
                            .font(.subheadline).foregroundStyle(Theme.stone)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("home.sessionRow")
            }
            if let error = viewModel.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle("Sessions")
        .onAppear { viewModel.refresh() }
    }
}
