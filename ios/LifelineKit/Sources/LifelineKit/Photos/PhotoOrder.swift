import Foundation

/// The order of a page's photos after a move. Pure: the shelf asks it, the store writes the answer.
public enum PhotoOrder {
    /// The order after `photo` moves to `index` (clamped to the row). Nil when the photo is not in the row or does not move.
    public static func moving(_ photo: PhotoID, to index: Int, in order: [PhotoID]) -> [PhotoID]? {
        guard let from = order.firstIndex(of: photo) else { return nil }
        let to = min(max(index, 0), order.count - 1)
        guard to != from else { return nil }
        var moved = order
        moved.remove(at: from)
        moved.insert(photo, at: to)
        return moved
    }
}
