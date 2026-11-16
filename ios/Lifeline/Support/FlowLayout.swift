import SwiftUI

/// Rows of items that wrap at the container's width. Chips must wrap, never scroll off
/// (design review 2026-10-22: readability).
/// An item wider than a row is offered the row's width, so its text wraps instead of running off.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, in: rowWidth(proposal)).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Arrange with the proposal that was measured, not `bounds.width`: the bounds are the reported
        // content width after rounding, and a hair less can push the last chip onto a row nobody measured.
        for item in arrange(subviews, in: rowWidth(proposal)).items {
            item.subview.place(at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                               proposal: ProposedViewSize(item.frame.size))
        }
    }

    /// No width proposed: one row, as wide as its items.
    private func rowWidth(_ proposal: ProposedViewSize) -> CGFloat { proposal.width ?? .infinity }

    /// Its ideal size, or the row's width with the height that needs, when the ideal is wider.
    private func size(of subview: LayoutSubview, in width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > width else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> (size: CGSize, items: [(subview: LayoutSubview, frame: CGRect)]) {
        var items: [(subview: LayoutSubview, frame: CGRect)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = size(of: subview, in: width)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append((subview, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), items)
    }
}
