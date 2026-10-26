import LifelineKit
import SwiftUI

/// Something the interviewer said, labeled "Lifeline". Quieter than the person's words: the prompt's
/// muted style on the Listen view, smaller still in a transcript. The identifier is on the words; a turn
/// the person spoke over is marked "cut off" beside the label, with the identifier plus ".interrupted".
struct TurnLine: View {
    let turn: InterviewerTurn
    var font: Font = .system(.subheadline, design: .serif)
    let identifier: String
    var marksCutOff = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Lifeline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.stone)
                if marksCutOff && turn.interrupted {
                    Text("cut off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(identifier).interrupted")
                }
            }
            Text(turn.text)
                .font(font)
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier(identifier)
        }
    }
}
