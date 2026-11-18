import LifelineKit
import SwiftUI

/// The card pinned under the Timeline's title (docs/design/TL_SpineStrip.dc.html): the whole life
/// as a strip, an olive frame over the years on screen, and the chapters those years touch. The
/// whole card is one button that opens the life map. The strip is not a scrubber: it takes no drag.
/// VoiceOver reads the card as one element, in the words of `TimelineCard.spokenText`.
struct TimelineCardView: View {
    let card: TimelineCard
    let onOpen: () -> Void
    /// The height `LifeStripView` gives the axis; it grows with Dynamic Type.
    @ScaledMetric(relativeTo: .footnote) private var axisHeight: CGFloat = 16
    private static let cornerRadius: CGFloat = 14
    private static let spacing: CGFloat = 4
    /// The room above the "During" line, which goes with it when there is no chapter.
    static let duringSpacingAbove: CGFloat = 6

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                LifeStripAxis(strip: card.strip, frame: card.frame)
                    .frame(height: axisHeight)
                    .accessibilityIdentifier("timeline.cardStrip")
                HStack(alignment: .firstTextBaseline) {
                    Text(String(card.strip.startYear))
                    Spacer()
                    Text("now")
                }
                .font(.footnote).monospacedDigit().foregroundStyle(Theme.secondaryText)
                // At the accessibility sizes a label may wrap once; the card must stay under half the screen.
                .lineLimit(2)
                DuringLine(card: card)
                    .padding(.top, Self.duringSpacingAbove - Self.spacing)
                    .accessibilityIdentifier("timeline.during")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
            .shadow(color: Theme.ink.opacity(0.10), radius: 5, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.spokenText)
        .accessibilityHint("Opens your chapters")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("timeline.card")
    }
}
