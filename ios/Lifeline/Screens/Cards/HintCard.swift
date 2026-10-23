import LifelineKit
import SwiftUI

/// "Sounds like it belongs here": one tap files the memory under the owner's own phrase.
struct HintCard: View {
    let hint: HintOut
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sounds like it belongs here")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.olive)
            Text(hint.kind == .collection ? "A collection: “\(hint.phrase)”" : "A chapter: “\(hint.phrase)”")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 12) {
                Button("Yes", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("card.hintYes")
                Button("Not quite", action: onDismiss)
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("card.hintNo")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.hint")
    }
}
