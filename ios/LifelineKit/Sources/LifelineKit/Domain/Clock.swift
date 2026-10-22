/// Milliseconds from the start of a session's audio file. The file is the clock.
public typealias Milliseconds = Int

/// A half-open range of file time: `start` inclusive, `end` exclusive.
public struct MsRange: Equatable, Hashable, Sendable, Codable {
    public var start: Milliseconds
    public var end: Milliseconds

    public init(start: Milliseconds, end: Milliseconds) {
        self.start = start
        self.end = end
    }

    public var duration: Milliseconds { max(0, end - start) }

    public func contains(_ ms: Milliseconds) -> Bool { ms >= start && ms < end }
}
