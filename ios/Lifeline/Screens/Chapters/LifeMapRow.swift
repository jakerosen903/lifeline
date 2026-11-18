import LifelineKit
import SwiftUI

/// One chapter on the life map: a bar from its first stated year to its last, and its name. The
/// whole row's width is the tap target. A chapter with no end has an open right edge, so colour is
/// never the only sign. At accessibility sizes the bar keeps its place and the name has its own line above it.
struct LifeMapRow: View {
    let row: LifeMap.Row
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
                        // Only the bar's place is read here: the name has its own line above it.
                        GeometryReader { geometry in
                            let layout = LifeMapRowLayout.place(start: row.start, end: row.end, width: geometry.size.width, nameWidth: 0)
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
                                      bottomTrailingRadius: row.isOpenEnded ? 0 : radius, topTrailingRadius: row.isOpenEnded ? 0 : radius)
            .fill(Theme.olive)
            .frame(width: width, height: barHeight)
    }
}
