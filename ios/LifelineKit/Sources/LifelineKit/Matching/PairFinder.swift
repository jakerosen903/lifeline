import Foundation

/// The numbers behind "Are these the same?" (M5).
public struct PairConfig: Sendable, Equatable {
    /// Neighbours per memory sent to the reconciler.
    public var pairTop = 3
    /// Floor on cosine, applied only when the embedder is calibrated.
    public var pairMin: Float = 0.55
    /// Pairs per reconciler call.
    public var pairBatch = 20
    /// Pair cards on the timeline at once.
    public var shownAtOnce = 3

    public init() {}
    public static let `default` = PairConfig()
}

/// The memory pairs worth asking the reconciler about: each eligible memory's nearest few,
/// never a pair already on file, never a hidden, excluded or stand-in memory. The older
/// memory is `a`.
public struct PairFinder: Sendable {
    public struct Candidate: Sendable, Equatable {
        public var a: Memory
        public var b: Memory
        public var score: Float
    }

    private let store: ExtractionStore
    private let matcher: MemoryMatcher
    private let config: PairConfig

    public init(store: ExtractionStore, matcher: MemoryMatcher, config: PairConfig = .default) {
        self.store = store; self.matcher = matcher; self.config = config
    }

    /// Best first.
    public func candidates() throws -> [Candidate] {
        let rows = try matcher.embedded().filter { !$0.memory.hiddenFromTimeline && !$0.memory.excludedFromAI && !$0.memory.isFloating }
        let known = try store.pairs.known()
        let calibrated = matcher.isCalibrated
        var seen = Set<PairKey>()
        var out: [Candidate] = []
        for (i, row) in rows.enumerated() {
            let neighbours = rows.enumerated()
                .filter { $0.offset != i }
                .map { (memory: $0.element.memory, score: Similarity.cosine(row.vector, $0.element.vector)) }
                .filter { !calibrated || $0.score >= config.pairMin }
                .sorted { $0.score > $1.score }
                .prefix(config.pairTop)
            for n in neighbours {
                let key = PairKey(row.memory.id, n.memory.id)
                guard !known.contains(key), seen.insert(key).inserted else { continue }
                let (older, newer) = Self.ordered(row.memory, n.memory)
                out.append(Candidate(a: older, b: newer, score: n.score))
            }
        }
        return out.sorted { $0.score > $1.score }
    }

    /// By creation, then by id so two memories created in the same instant still order the same way.
    static func ordered(_ x: Memory, _ y: Memory) -> (Memory, Memory) {
        if x.createdAt != y.createdAt { return x.createdAt < y.createdAt ? (x, y) : (y, x) }
        return x.id.rawValue < y.id.rawValue ? (x, y) : (y, x)
    }
}
