import CoreGraphics
import LifelineKit

/// One drag on the photo row, in the row's own coordinates: the photo that moves, where it started and where the
/// finger is now. It answers the two things the row draws: the slot under the finger, and how far the tile is
/// from its slot. The order itself comes from the kit (`PhotoOrder`).
struct PhotoRowDrag: Equatable {
    let photo: PhotoID
    /// The tile's place in the row when the drag began.
    let from: Int
    let startX: CGFloat
    var currentX: CGFloat

    /// The index of the slot under the finger, clamped to the row: past either end is the end.
    func target(count: Int, stride: CGFloat) -> Int {
        guard count > 0, stride > 0 else { return 0 }
        return min(max(Int((currentX / stride).rounded(.down)), 0), count - 1)
    }

    /// How far the tile is drawn from the slot it shows in, so it stays under the finger while the others make room.
    func offset(count: Int, stride: CGFloat) -> CGFloat {
        CGFloat(from - target(count: count, stride: stride)) * stride + (currentX - startX)
    }
}
