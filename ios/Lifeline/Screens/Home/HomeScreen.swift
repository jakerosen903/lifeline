import LifelineKit
import SwiftUI

/// Past sessions, newest first, and the Start button.
struct HomeScreen: View {
    @Bindable var viewModel: HomeViewModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    if viewModel.rows.isEmpty {
                        ContentUnavailableView("No sessions yet", systemImage: "waveform",
                                               description: Text("Tap Start and tell me about the house you grew up in."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(viewModel.rows) { row in
                        NavigationLink(value: row.session) {
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
                    Color.clear.frame(height: 120).listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)

                Button {
                    Task { await viewModel.startSession() }
                } label: {
                    Label("Start", systemImage: "mic.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 140, height: 140)
                        .background(Circle().fill(Theme.olive))
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("home.start")
                .padding(.bottom, 24)
            }
            .linenBackground()
            .navigationTitle("Lifeline")
            .navigationDestination(for: Session.self) { session in
                SessionDetailScreen(viewModel: SessionDetailViewModel(session: session, deps: viewModel.deps))
            }
            .toolbar {
                NavigationLink { PeopleScreen(viewModel: PeopleViewModel(deps: viewModel.deps)) } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityIdentifier("home.people")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityIdentifier("home.settings")
            }
            .sheet(isPresented: $showSettings) {
                SettingsScreen(deps: viewModel.deps)
            }
            .fullScreenCover(item: $viewModel.activeSession) { session in
                SessionScreen(viewModel: session) { viewModel.sessionEnded() }
            }
            .onAppear { viewModel.refresh() }
        }
    }
}

extension Session: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
