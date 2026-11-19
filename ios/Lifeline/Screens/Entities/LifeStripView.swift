import LifelineKit
import SwiftUI

/// The life strip on an entity page (S2): a thin axis from the first year to now with a mark per
/// dated moment, and the sentence that says the same in words. A guessed mark is hollow, so
/// uncertainty is a shape as well as a word (PRINCIPLES 5). With fewer than two dated moments
/// only the sentence shows.
struct LifeStripView: View {
    let strip: LifeStrip
    /// The axis grows with Dynamic Type; the marks and the span bar keep their proportions to it.
    @ScaledMetric(relativeTo: .footnote) private var axisHeight: CGFloat = 16

    var body: some View {
        if strip.showsAxis {
            VStack(alignment: .leading, spacing: 4) {
                LifeStripAxis(strip: strip).frame(height: axisHeight)
                HStack {
                    Text(String(strip.startYear))
                    Spacer()
                    Text("now")
                }
                .font(.footnote).monospacedDigit().foregroundStyle(Theme.secondaryText)
                sentence
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strip.sentence ?? "")
            .accessibilityIdentifier("entity.strip")
        } else if strip.sentence != nil {
            sentence.accessibilityIdentifier("entity.stripSentence")
        }
    }

    private var sentence: some View {
        Text(strip.sentence ?? "").font(.footnote).foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
