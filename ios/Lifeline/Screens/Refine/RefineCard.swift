import LifelineKit
import SwiftUI

/// The one question that can narrow a range, as a choice between things the owner said.
struct RefineCard: View {
    let title: String
    let bestGuess: String
    let question: RelativeQuestion?
    let onChoose: (RelativeQuestion.Choice) -> Void
    let onKeep: () -> Void
    /// "Tell me when": the person gives the date themselves (M4.1). Nil where that is not offered.
    var onTellMeWhen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When was this?").font(.caption.weight(.semibold)).foregroundStyle(Theme.ochreText)
            Text(title).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                Text("Best guess so far").font(.caption).foregroundStyle(Theme.secondaryText)
                Text(bestGuess).font(.subheadline).foregroundStyle(Theme.ochreText)
            }
            if let question {
                Text("Narrow it down").font(.caption).foregroundStyle(Theme.secondaryText).padding(.top, 4)
                Text(question.prompt).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    ForEach(question.choices) { choice in
                        Button(choice.label) { onChoose(choice) }
                            .buttonStyle(.bordered)
                            .tint(Theme.oliveOnFill)
                            .accessibilityIdentifier("refine.choice")
                    }
                }
            } else if onTellMeWhen == nil {
                Text("Nothing you've said so far can narrow this. Keep telling your story.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let onTellMeWhen {
                Button("Tell me when", systemImage: "calendar", action: onTellMeWhen)
                    .buttonStyle(.bordered)
                    .tint(Theme.oliveOnFill)
                    .accessibilityIdentifier("refine.tellMeWhen")
            }
            Button("Keep “\(bestGuess)” for now", action: onKeep)
                .buttonStyle(.borderless)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("refine.keep")
            Text("You can always come back to this.").font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.question")
    }
}
