import LifelineKit
import SwiftUI

/// Where a row's bar and name go across the map's width. Pure, so the arithmetic reads on its own.
struct LifeMapRowLayout: Equatable {
    enum NamePlace: Equatable { case inside, after, before }

    /// A one-year chapter, or one that starts after now, is still a bar you can see.
    static let minimumBarWidth: CGFloat = 8
    static let gap: CGFloat = 6
    static let insidePadding: CGFloat = 8

    let barX: CGFloat
    let barWidth: CGFloat
    let namePlace: NamePlace
    let nameX: CGFloat
    /// The room the name has; a longer name truncates on one line.
    let nameWidth: CGFloat

    /// `start` and `end` are 0...1 along the axis. The name goes inside the bar when it fits, else to
    /// its right; when the bar reaches the right edge and leaves more room on its left, to its left.
    static func place(start: Double, end: Double, width: CGFloat, nameWidth: CGFloat) -> LifeMapRowLayout {
        let barWidth = min(max(CGFloat(end - start) * width, minimumBarWidth), width)
        let barX = min(max(CGFloat(start) * width, 0), width - barWidth)
        if nameWidth + 2 * insidePadding <= barWidth {
            return LifeMapRowLayout(barX: barX, barWidth: barWidth, namePlace: .inside,
                                    nameX: barX + insidePadding, nameWidth: barWidth - 2 * insidePadding)
        }
        let after = max(width - (barX + barWidth) - gap, 0)
        let before = max(barX - gap, 0)
        if after >= nameWidth || after >= before {
            return LifeMapRowLayout(barX: barX, barWidth: barWidth, namePlace: .after, nameX: barX + barWidth + gap, nameWidth: after)
        }
        let room = min(nameWidth, before)
        return LifeMapRowLayout(barX: barX, barWidth: barWidth, namePlace: .before, nameX: barX - gap - room, nameWidth: room)
    }
}

/// One chapter on the life map: a bar from its first stated year to its last, and its name. The
/// whole row's width is the tap target. A chapter with no end has an open right edge, so colour is
/// never the only sign. At accessibility sizes the bar keeps its place and the name has its own line above it.
struct LifeMapRow: View {
    let row: LifeMap.Row
    let isOpenEnded: Bool
    /// `LifeMap.summary(of:)`: the name, the years, and the count of moments.
    let label: String
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var scaledBarHeight: CGFloat = 20
    @State private var measuredNameWidth: CGFloat = 0

    /// Tall enough for the name inside it; capped, so at the largest sizes the bar stays a bar.
    private var barHeight: CGFloat { min(scaledBarHeight, 28) }

    var body: some View {
        Button(action: onTap) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        nameText.foregroundStyle(Theme.ink)
                        GeometryReader { geometry in
                            let layout = LifeMapRowLayout.place(start: row.start, end: row.end, width: geometry.size.width, nameWidth: .infinity)
                            bar(width: layout.barWidth).offset(x: layout.barX)
                        }
                        .frame(height: barHeight)
                    }
                    .padding(.vertical, 8)
                } else {
                    GeometryReader { geometry in
                        let layout = LifeMapRowLayout.place(start: row.start, end: row.end, width: geometry.size.width, nameWidth: measuredNameWidth)
                        ZStack(alignment: .leading) {
                            bar(width: layout.barWidth).offset(x: layout.barX)
                            nameText
                                .foregroundStyle(layout.namePlace == .inside ? Theme.card : Theme.ink)
                                .frame(width: layout.nameWidth, alignment: layout.namePlace == .before ? .trailing : .leading)
                                .offset(x: layout.nameX)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: max(44, barHeight + 16))
                    // The name's own width, measured off screen, decides whether it fits inside the bar.
                    .background(alignment: .leading) {
                        nameText.fixedSize().hidden()
                            .onGeometryChange(for: CGFloat.self, of: \.size.width) { measuredNameWidth = $0 }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("lifemap.row")
    }

    private var nameText: some View {
        Text(row.title)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func bar(width: CGFloat) -> some View {
        let radius = barHeight / 2
        return UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                      bottomTrailingRadius: isOpenEnded ? 0 : radius, topTrailingRadius: isOpenEnded ? 0 : radius)
            .fill(Theme.olive)
            .frame(width: width, height: barHeight)
    }
}
