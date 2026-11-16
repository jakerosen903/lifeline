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
                axis.frame(height: axisHeight)
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

    private var axis: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let markHeight = height * 0.75
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.ink.opacity(0.4))
                    .frame(width: width, height: 1).offset(y: height / 2 - 0.5)
                if let span = strip.statedSpan {
                    Capsule().fill(Theme.olive)
                        .frame(width: max((span.upperBound - span.lowerBound) * width, height / 3), height: height / 3)
                        .offset(x: span.lowerBound * width, y: height / 3)
                }
                ForEach(Array(strip.marks.enumerated()), id: \.offset) { _, mark in
                    // Marks grow in height only, so close years stay apart at large text sizes.
                    // A hollow mark is a little wider, so its outline reads as a shape.
                    let markWidth: CGFloat = mark.isGuess ? 6 : 4
                    // Its centre sits at its position, kept inside the strip at either end.
                    let centre = min(max(mark.position * width, markWidth / 2), width - markWidth / 2)
                    let shape = RoundedRectangle(cornerRadius: markWidth / 2)
                    Group {
                        if mark.isGuess {
                            shape.strokeBorder(Theme.ochreText, lineWidth: 1.5).background(shape.fill(Theme.linen))
                        } else {
                            shape.fill(Theme.ochreText)
                        }
                    }
                    .frame(width: markWidth, height: markHeight)
                    .offset(x: centre - markWidth / 2, y: (height - markHeight) / 2)
                }
            }
        }
    }
}
