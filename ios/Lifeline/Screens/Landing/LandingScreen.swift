import LifelineKit
import SwiftUI

/// "Your recording is saved." A few moments from today, playable; Done for now is the default.
struct LandingScreen: View {
    let viewModel: LandingViewModel
    /// Called once with whether the person chose "Tell another".
    let onClose: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let line = viewModel.crisisLine {
                        Link(destination: URL(string: "tel:\(line.number)")!) {
                            Label("If you need to talk to someone now: \(line.label), call or text \(line.number).", systemImage: "phone")
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                        }
                        .tint(Theme.olive)
                        .accessibilityIdentifier("landing.crisisLine")
                    }
                    Text(viewModel.headline).titleStyle().accessibilityIdentifier("landing.headline")
                    if !viewModel.rows.isEmpty {
                        Text(viewModel.isFirst && !viewModel.heavy ? "Here it is, in your voice." : "A few moments from today.")
                            .font(.system(.body, design: .serif)).foregroundStyle(Theme.stone)
                    }
                    if viewModel.stillSorting != nil {
                        Text("Sorting them is still going on in the background. You don't have to do anything now.")
                            .font(.footnote).foregroundStyle(Theme.stone)
                    }
                    ForEach(viewModel.rows) { row in
                        momentRow(row)
                    }
                    if let more = viewModel.moreText {
                        Text(more).font(.footnote).foregroundStyle(Theme.stone)
                    }
                    if let sorting = viewModel.stillSorting {
                        Label(sorting, systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote).foregroundStyle(Theme.ochre)
                            .accessibilityIdentifier("landing.stillSorting")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Before you go").font(.caption.weight(.semibold)).foregroundStyle(Theme.olive)
                        Text(viewModel.closingLine)
                            .font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("landing.closing")
                        if viewModel.heavy {
                            Text("If you ever want to talk to a person, I can show you who to call.")
                                .font(.footnote).foregroundStyle(Theme.stone)
                        }
                    }
                    .padding(.top, 8)
                    choices
                    if let error = viewModel.error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("landing.error")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .linenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(get: { reviewing }, set: { reviewing = $0 })) {
                SessionDetailScreen(viewModel: SessionDetailViewModel(session: viewModel.session, deps: viewModel.deps))
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: viewModel.finished) { if let another = viewModel.finished { onClose(another) } }
        .onDisappear { viewModel.stop() }
        .confirmationDialog("Delete today's recording?", isPresented: Binding(get: { viewModel.confirmingDelete }, set: { viewModel.confirmingDelete = $0 }),
                            titleVisibility: .visible) {
            Button("Delete the recording and everything from it", role: .destructive) { Task { await viewModel.deleteToday() } }
                .accessibilityIdentifier("landing.confirmDelete")
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The audio, the words and the \(viewModel.rows.count + viewModel.more) moments from today go. This cannot be undone.")
        }
    }

    @State private var reviewing = false

    private func momentRow(_ row: LandingRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { viewModel.toggle(row) } label: {
                Image(systemName: viewModel.isPlaying(row) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.olive)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("landing.play")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    if !row.isKept {
                        Text("possible").font(.caption2.weight(.semibold)).foregroundStyle(Theme.ochre)
                    }
                }
                Text("“\(row.quote)”").font(.system(.subheadline, design: .serif)).foregroundStyle(Theme.stone).lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("landing.row")
    }

    private var choices: some View {
        VStack(spacing: 12) {
            if viewModel.isFirst && !viewModel.heavy {
                Button { viewModel.tellAnother() } label: {
                    Text("Tell another").font(.headline).frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.olive)).foregroundStyle(.white)
                }
                .accessibilityIdentifier("landing.tellAnother")
            }
            Button { viewModel.doneForNow() } label: {
                Text("Done for now").font(.headline).frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(viewModel.isFirst && !viewModel.heavy ? Theme.sand : Theme.olive))
                    .foregroundStyle(viewModel.isFirst && !viewModel.heavy ? Theme.ink : .white)
            }
            .accessibilityIdentifier("landing.done")
            Button("Review these moments") { reviewing = true }
                .buttonStyle(.bordered)
                .tint(Theme.olive)
                .accessibilityIdentifier("landing.review")
            HStack(spacing: 20) {
                Button("Hide today from the timeline") { viewModel.hideToday() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("landing.hide")
                Button("Delete today's recording…", role: .destructive) { viewModel.confirmingDelete = true }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("landing.delete")
            }
            .font(.footnote)
        }
        .padding(.top, 8)
    }
}
