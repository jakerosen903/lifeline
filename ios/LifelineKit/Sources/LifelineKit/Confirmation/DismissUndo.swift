import Foundation

/// Dismiss is reversible for a moment: the last dismissed item can be taken back within the
/// window. Pure; the caller supplies the clock. One item at a time: a second dismiss replaces
/// the first, which is then gone from the review view (and still in Sessions → Dismissed).
public struct DismissUndo<Item: Equatable & Sendable>: Equatable, Sendable {
    public let window: Duration
    private var item: Item?
    private var at: Date?

    public init(window: Duration = .seconds(6)) { self.window = window }

    public mutating func dismissed(_ item: Item, at date: Date) {
        self.item = item
        self.at = date
    }

    public func available(at date: Date) -> Item? {
        guard let item, let at, date.timeIntervalSince(at) <= window.seconds else { return nil }
        return item
    }

    /// The item if still within the window, and nothing after.
    public mutating func take(at date: Date) -> Item? {
        defer { clear() }
        return available(at: date)
    }

    public mutating func clear() {
        item = nil
        at = nil
    }
}

extension Duration {
    var seconds: TimeInterval { TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18 }
}
