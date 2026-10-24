import LifelineKit
import SwiftUI

/// "Which part of the recording": the telling's words in order, the span's words highlighted.
/// Tap a word, then "Start here" or "End here"; Play plays the draft; Save writes it (M6). A
/// telling told across a pause is edited one part at a time.
struct TrimSheet: View {
    let parts: [ChangeViewModel.Part]
    let deps: Dependencies
    let title: String
    let onSave: (_ order: Int, _ startWord: Int, _ endWord: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var partIndex = 0
    @State private var start = 0
    @State private var end = 0
    @State private var selected: Int?
    @State private var player = SegmentPlayer()

    private var part: ChangeViewModel.Part? { parts.indices.contains(partIndex) ? parts[partIndex] : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if parts.count > 1 {
                        Picker("Part", selection: $partIndex) {
                            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in Text(p.title).tag(i) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("trim.part")
                    }
                    if let part {
                        Text(rangeText(part)).font(.subheadline).foregroundStyle(Theme.ochre).accessibilityIdentifier("trim.range")
                        FlowLayout(spacing: 6) {
                            ForEach(Array(part.words.enumerated()), id: \.offset) { i, word in
                                Button(word.text) { selected = i }
                                    .buttonStyle(.plain)
                                    .font(.system(.body, design: .serif))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(background(for: i)))
                                    .foregroundStyle(Theme.ink)
                                    .accessibilityIdentifier("trim.word")
                            }
                        }
                        HStack(spacing: 12) {
                            Button("Start here") { if let s = selected { start = s; if end < s { end = s } } }
                                .disabled(selected == nil).accessibilityIdentifier("trim.setStart")
                            Button("End here") { if let s = selected { end = s; if start > s { start = s } } }
                                .disabled(selected == nil).accessibilityIdentifier("trim.setEnd")
                            Spacer()
                            Button(player.isPlaying ? "Stop" : "Play", systemImage: player.isPlaying ? "stop.circle.fill" : "play.circle.fill") { togglePlay(part) }
                                .accessibilityIdentifier("trim.play")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.olive)
                    }
                }
                .padding(24)
            }
            .linenBackground()
            .navigationTitle("Which part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { player.stop(); dismiss() }.accessibilityIdentifier("trim.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let part { player.stop(); onSave(part.span.order, start, end); dismiss() } }
                        .disabled(part == nil || start > end)
                        .accessibilityIdentifier("trim.save")
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { load() }
        .onChange(of: partIndex) { load() }
        .onDisappear { player.stop() }
    }

    private func load() {
        guard let part, let covered = part.covered else { start = 0; end = 0; selected = nil; return }
        start = covered.lowerBound; end = covered.upperBound; selected = nil
    }

    private func background(for i: Int) -> Color {
        if i == selected { return Theme.olive.opacity(0.35) }
        return (start...max(start, end)).contains(i) ? Theme.sand : Theme.linen
    }

    private func rangeText(_ part: ChangeViewModel.Part) -> String {
        guard !part.words.isEmpty else { return "" }
        let s = min(max(start, 0), part.words.count - 1), e = min(max(end, s), part.words.count - 1)
        return "From “\(part.words[s].text)” to “\(part.words[e].text)”" + (e == s ? "" : "") 
    }

    private func togglePlay(_ part: ChangeViewModel.Part) {
        if player.isPlaying { player.stop(); return }
        guard !part.words.isEmpty, let segment = try? deps.extractionStore.sessions.fetchSegment(part.span.segmentID),
              let session = try? deps.extractionStore.sessions.fetch(segment.sessionID) else { return }
        let s = min(max(start, 0), part.words.count - 1), e = min(max(end, s), part.words.count - 1)
        try? deps.activatePlayback()
        try? player.play(url: try deps.audioURL(for: session), range: MsRange(start: part.words[s].startMs, end: part.words[e].endMs))
    }
}
