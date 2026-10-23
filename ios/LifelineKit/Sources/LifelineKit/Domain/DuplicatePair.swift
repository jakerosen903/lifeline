import Foundation

/// What the reconciler said two memories are to each other.
public enum PairVerdict: String, Codable, Sendable {
    case sameMoment = "same_moment"
    case sameStory = "same_story"
    case different
}

/// Where a pair stands with the person. `open` waits on a card; the rest are decided and
/// never asked again.
public enum PairStatus: String, Codable, Sendable {
    case open, merged, separate, grouped
}

/// Two memories the pass found close and the reconciler judged. `a` is the older memory.
public struct DuplicatePair: Codable, Sendable, Equatable, Identifiable {
    public var id: DuplicatePairID
    public var aMemoryID: MemoryID
    public var bMemoryID: MemoryID
    public var score: Float
    public var verdict: PairVerdict
    public var status: PairStatus
    public var decidedAt: Date?

    public init(id: DuplicatePairID, aMemoryID: MemoryID, bMemoryID: MemoryID, score: Float, verdict: PairVerdict,
                status: PairStatus, decidedAt: Date?) {
        self.id = id; self.aMemoryID = aMemoryID; self.bMemoryID = bMemoryID; self.score = score; self.verdict = verdict
        self.status = status; self.decidedAt = decidedAt
    }

    public var key: PairKey { PairKey(aMemoryID, bMemoryID) }
}

/// An unordered pair of memory ids, so (a, b) and (b, a) are the same key.
public struct PairKey: Hashable, Sendable {
    public let low: MemoryID
    public let high: MemoryID

    public init(_ x: MemoryID, _ y: MemoryID) {
        if x.rawValue <= y.rawValue { low = x; high = y } else { low = y; high = x }
    }
}
