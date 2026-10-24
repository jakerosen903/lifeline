import LifelineKit
import SwiftUI

/// What a pair card needs from the store: the two memories and when each was first told.
struct PairRow: Identifiable, Equatable {
    let pair: DuplicatePair
    let a: Memory
    let b: Memory
    let aRecordedAt: Date?
    let bRecordedAt: Date?
    var id: DuplicatePairID { pair.id }
}

/// "Are these the same?": two memories the reconciler called one moment, each with Play, and
/// two answers. A pair it called one story asks "Sounds like one story" instead (M5).
struct PairCard: View {
    let row: PairRow
    let isPlaying: (MemoryID) -> Bool
    let onPlay: (MemoryID) -> Void
    let onSame: () -> Void
    let onSeparate: () -> Void

    private var isStory: Bool { row.pair.verdict == .sameStory }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isStory ? "Sounds like one story" : "Are these the same?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.olive)
            side(row.a, recordedAt: row.aRecordedAt)
            side(row.b, recordedAt: row.bRecordedAt)
            HStack(spacing: 12) {
                Button(isStory ? "One story" : "Same story", action: onSame)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.olive)
                    .accessibilityIdentifier(isStory ? "pair.group" : "pair.same")
                Button("Keep separate", action: onSeparate)
                    .buttonStyle(.bordered)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("pair.separate")
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pair.card")
    }

    private func side(_ memory: Memory, recordedAt: Date?) -> some View {
        HStack(spacing: 10) {
            Button { onPlay(memory.id) } label: {
                Image(systemName: isPlaying(memory.id) ? "stop.circle.fill" : "play.circle.fill").font(.title2)
            }
            .tint(Theme.olive)
            .accessibilityLabel(isPlaying(memory.id) ? "Stop" : "Play")
            .accessibilityIdentifier("pair.play")
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let recordedAt {
                    Text("recorded " + recordedAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(Theme.stone)
                }
            }
        }
    }
}
