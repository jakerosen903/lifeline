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
    private var lines: Int { typeSize.isAccessibilitySize ? 2 : 1 }

    var body: some View {
        if !card.during.isEmpty {
            // A hidden text of `lines` lines in the names' font sets the height every try must fit in.
            // `ViewThatFits(in: .horizontal)` alone cannot allow a second line: it measures one line's width.
            Text(verbatim: Array(repeating: "A", count: lines).joined(separator: "\n"))
                .font(Self.namesFont)
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
