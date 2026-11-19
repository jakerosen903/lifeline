import LifelineKit
import SwiftUI

/// "During Maple Street · Summers at the lake  +2": the chapters the card's frame touches, longest
/// first. As many names as fit show; the rest become "+N" at the trailing edge. With only one name
/// left, that name truncates. At the accessibility sizes each try may take two lines before a
/// name drops. With no chapter there is nothing: no "During" word, no empty line.
struct DuringLine: View {
    let card: TimelineCard
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let namesFont = Font.subheadline.weight(.semibold)

    /// How many lines the names may take before one fewer name is tried.
    private var lines: Int { Self.lines(at: typeSize) }
    fileprivate static func lines(at typeSize: DynamicTypeSize) -> Int { typeSize.isAccessibilitySize ? 2 : 1 }

    var body: some View {
        if !card.during.isEmpty {
            // A hidden text of `lines` lines in the names' font sets the height every try must fit in.
            // `ViewThatFits(in: .horizontal)` alone cannot allow a second line: it measures one line's width.
            Self.reference(lines: lines)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    ViewThatFits(in: .vertical) {
                        ForEach(Array((1...card.during.count).reversed()), id: \.self) { count in
                            line(showing: count)
                        }
                    }
                }
        }
    }

    /// A text `lines` lines tall in the names' font: the tallest names text at that many lines.
    fileprivate static func reference(lines: Int) -> Text {
        Text(verbatim: Array(repeating: "A", count: lines).joined(separator: "\n")).font(namesFont)
    }

    /// The first `count` names. Only the last try (one name) has a line limit: an earlier one
    /// that would need more lines must not fit, so that the next try is made.
    private func line(showing count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("During")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize()
            Text(card.duringText(showing: count) ?? "")
                .font(Self.namesFont)
                .foregroundStyle(Theme.oliveText)
                .lineLimit(count == 1 ? lines : nil)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let overflow = card.overflow(showing: count) {
                Text(overflow)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize()
            }
        }
    }
}

/// Measures the tallest the "During" line can be at the current text size and reports it. Hidden,
/// and laid out as a background, so it takes no room. It is measured whether or not the line shows.
struct DuringLineTallest: View {
    let onChange: (CGFloat) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        DuringLine.reference(lines: DuringLine.lines(at: typeSize))
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onChange($0) }
            .accessibilityHidden(true)
    }
}
