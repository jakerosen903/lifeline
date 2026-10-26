import LifelineKit
import SwiftUI

/// Something the interviewer said, labeled "Lifeline". Quieter than the person's words: the prompt's
/// muted style on the Listen view, smaller still in a transcript. The identifier is on the words.
struct TurnLine: View {
    let turn: InterviewerTurn
    var font: Font = .system(.subheadline, design: .serif)
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Lifeline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.stone)
            Text(turn.text)
                .font(font)
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier(identifier)
        }
    }
}
