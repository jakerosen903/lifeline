import Foundation

/// One drag on the photo shelf, in the shelf's own coordinates: the photo that moves, where it started and where the
/// finger is now. Pure: it answers the two things the shelf draws, the slot under the finger and how far the tile is
/// from its slot. The order itself comes from `PhotoOrder`.
public struct PhotoShelfDrag: Sendable, Equatable {
    public let photo: PhotoID
    /// The tile's place in the row when the drag began.
    public let from: Int
    public let startX: Double
    public var currentX: Double

    public init(photo: PhotoID, from: Int, startX: Double, currentX: Double) {
        self.photo = photo; self.from = from; self.startX = startX; self.currentX = currentX
    }

    /// The index of the slot under the finger. Slot i covers [i × stride, (i + 1) × stride): a finger on a boundary is in
    /// the slot after it. Clamped to the row: before the first tile is the first slot, past the last is the last.
    /// An empty row or no stride gives 0.
    public func target(count: Int, stride: Double) -> Int {
        guard count > 0, stride > 0 else { return 0 }
        return min(max(Int((currentX / stride).rounded(.down)), 0), count - 1)
    }

    /// How far the tile is drawn from the slot it shows in, so it stays under the finger while the others make room.
    public func offset(count: Int, stride: Double) -> Double {
        Double(from - target(count: count, stride: stride)) * stride + (currentX - startX)
    }
}
