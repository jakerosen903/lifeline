import LifelineKit
import SwiftUI

/// The mark on the spine that says how sure a date is. The three marks differ by shape, never by
/// colour alone (PRINCIPLES 5): a ring with a solid line, a ring with a dashed line, and a dashed
/// capsule along the spine for more than one year. The linen fill covers the spine behind it.
struct SpineMark: View {
    let mark: SpineLayout.Mark

    /// The width of every mark, and the height of a dot.
    nonisolated static let size: CGFloat = 14
    /// The capsule's height: a range reads as a stretch of the spine.
    static let capsuleHeight: CGFloat = 36
    private static let lineWidth: CGFloat = 2

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: Self.size / 2)
        outline
            .fill(Theme.linen)
            .overlay(outline.strokeBorder(Theme.ink, style: stroke))
            .frame(width: Self.size, height: mark == .dashedCapsule ? Self.capsuleHeight : Self.size)
    }

    private var stroke: StrokeStyle {
        switch mark {
        case .solidDot: StrokeStyle(lineWidth: Self.lineWidth)
        case .dashedDot: StrokeStyle(lineWidth: Self.lineWidth, dash: [3, 2])
        case .dashedCapsule: StrokeStyle(lineWidth: Self.lineWidth, dash: [4, 3])
        }
    }
}
