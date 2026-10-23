import LifelineKit
import SwiftUI

/// The one question that can narrow a range, as a choice between things the owner said.
struct RefineCard: View {
    let title: String
    let bestGuess: String
    let question: RelativeQuestion?
    let onChoose: (RelativeQuestion.Choice) -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When was this?").font(.caption.weight(.semibold)).foregroundStyle(Theme.ochre)
            Text(title).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                Text("Best guess so far").font(.caption).foregroundStyle(Theme.stone)
                Text(bestGuess).font(.subheadline).foregroundStyle(Theme.ochre)
            }
            if let question {
                Text("Narrow it down").font(.caption).foregroundStyle(Theme.stone).padding(.top, 4)
                Text(question.prompt).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    ForEach(question.choices) { choice in
                        Button(choice.label) { onChoose(choice) }
                            .buttonStyle(.bordered)
                            .tint(Theme.olive)
                            .accessibilityIdentifier("refine.choice")
                    }
                }
            } else {
                Text("Nothing you've said so far can narrow this. Keep telling your story.")
                    .font(.footnote).foregroundStyle(Theme.stone)
            }
            Button("Keep “\(bestGuess)” for now", action: onKeep)
                .font(.footnote)
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier("refine.keep")
            Text("You can always come back to this.").font(.caption2).foregroundStyle(Theme.stone)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.question")
    }
}
