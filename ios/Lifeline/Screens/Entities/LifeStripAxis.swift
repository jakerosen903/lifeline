import LifelineKit
import SwiftUI

/// The strip's axis (S2): a line from the first year to now, the stated span, a mark per dated
/// moment and, when `frame` is set, an olive outline over the years it covers. A guessed mark is
/// hollow, so uncertainty is a shape as well as a colour (PRINCIPLES 5). The frame is never
/// filled, so the marks stay visible inside it.
struct LifeStripAxis: View {
    let strip: LifeStrip
    /// Positions on the axis, 0...1. Nil draws no frame.
    var frame: ClosedRange<Double>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The frame is never narrower than this, so a one-year frame stays visible.
    private static let smallestFrameWidth: CGFloat = 10

    var body: some View {
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
                if let frame {
                    let box = Self.frameBox(frame, width: width)
                    RoundedRectangle(cornerRadius: height / 4)
                        .strokeBorder(Theme.olive, lineWidth: 2)
                        .frame(width: box.width, height: height)
                        .offset(x: box.minX)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: frame)
    }

    /// The frame's horizontal extent: widened to the smallest width about its centre, then
    /// shifted to stay inside 0...width. A strip narrower than the smallest width gets all of it.
    static func frameBox(_ frame: ClosedRange<Double>, width: CGFloat) -> (minX: CGFloat, width: CGFloat) {
        let boxWidth = min(max((frame.upperBound - frame.lowerBound) * width, smallestFrameWidth), max(width, 0))
        let centre = (frame.lowerBound + frame.upperBound) / 2 * width
        let minX = min(max(centre - boxWidth / 2, 0), max(width - boxWidth, 0))
        return (minX, boxWidth)
    }
}
