/// How many pieces of one kind of work are running, so a "working…" line stays until the last one ends.
/// Each `begin()` is paired with one `end()`.
public struct InFlightCount: Sendable, Equatable {
    public private(set) var count = 0

    public init() {}

    public var isActive: Bool { count > 0 }

    public mutating func begin() { count += 1 }

    /// An unmatched `end()` is a caller's bug; it never makes the count negative, so a later `begin()` still shows.
    public mutating func end() { count = max(0, count - 1) }
}
