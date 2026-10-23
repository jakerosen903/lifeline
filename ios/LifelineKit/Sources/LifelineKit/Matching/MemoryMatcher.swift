import Foundation

/// The numbers behind "Same as X?". Starting points, tuned on the owner's recordings.
public struct MatchConfig: Sendable, Equatable {
    /// Memories at least this similar to a segment ride in the extractor's packet.
    public var retrieveMin: Float = 0.55
    public var retrieveCount: Int = 5
    /// A card gets the "Same as X?" line on vectors alone only above this.
    public var suggestMin: Float = 0.80
    public var pickerCount: Int = 3

    public init() {}
    public static let `default` = MatchConfig()
}

/// A memory a card might be a retelling of, and how the app came to think so.
public struct MemoryMatch: Equatable, Sendable, Identifiable {
    public enum Source: Sendable, Equatable { case extractor, embedding }
    public var memoryID: MemoryID
    public var title: String
    /// When the memory was first told: the session start of its order-0 span.
    public var recordedAt: Date?
    public var score: Float
    public var source: Source
    public var id: MemoryID { memoryID }

    public init(memoryID: MemoryID, title: String, recordedAt: Date?, score: Float, source: Source) {
        self.memoryID = memoryID; self.title = title; self.recordedAt = recordedAt; self.score = score; self.source = source
    }
}

/// Finds the earlier memories a telling might belong to. Retrieval is cosine over on-device
/// sentence embeddings; the extractor decides with those in its packet; the person confirms.
/// A memory excluded from AI is never embedded, retrieved or suggested. A hidden memory is
/// never suggested on a card and sits in the picker only when asked for.
public struct MemoryMatcher: Sendable {
    private let store: ExtractionStore
    private let embedder: (any SentenceEmbedder)?
    private let config: MatchConfig

    public init(store: ExtractionStore, embedder: (any SentenceEmbedder)?, config: MatchConfig = .default) {
        self.store = store; self.embedder = embedder; self.config = config
    }

    /// The one text a memory is embedded from, so the card and the memory compare like with like.
    public static func text(title: String, quote: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return q }
        if q.isEmpty { return t }
        return "\(t). \(q)"
    }

    /// Writes the memory's vector, or removes it when the memory is excluded from AI or the
    /// embedder has nothing to say.
    public func index(_ memory: Memory) throws {
        guard let embedder, !memory.excludedFromAI,
              let vector = embedder.vector(for: Self.text(title: memory.title, quote: memory.summaryQuote)) else {
            try store.embeddings.delete(memory: memory.id)
            return
        }
        try store.embeddings.upsert(memory: memory.id, model: embedder.model, vector: vector)
    }

    /// Every memory without a row gets one. Returns how many were written.
    public func backfill() throws -> Int {
        guard let embedder else { return 0 }
        // Per model: a new asset version or a second language re-embeds everything once.
        let done = try store.embeddings.memoryIDsWithRows(model: embedder.model)
        var written = 0
        for memory in try store.memories.allMemories() where !done.contains(memory.id) && !memory.excludedFromAI {
            try index(memory)
            if try store.embeddings.vector(of: memory.id) != nil { written += 1 }
        }
        return written
    }

    /// The nearest earlier memories to a segment's words, for the packet.
    public func related(to text: String, excluding: Set<MemoryID> = []) throws -> [Memory] {
        try scored(text, excluding: excluding)
            .filter { $0.score >= config.retrieveMin }
            .prefix(config.retrieveCount)
            .map(\.memory)
    }

    /// What the card says. The extractor's answer first, then vectors above `suggestMin`.
    /// Never a hidden or excluded memory, never one that no longer exists.
    public func suggestion(for card: MemoryOut, extractorSameAs: MemoryID?) throws -> MemoryMatch? {
        if let extractorSameAs, let memory = try store.memories.fetch(extractorSameAs), eligible(memory, includeHidden: false) {
            return try match(memory, score: 1, source: .extractor)
        }
        let text = Self.text(title: card.title, quote: card.quote)
        guard embedder?.suggestsOnItsOwn == true,
              let best = try scored(text, excluding: []).first(where: { eligible($0.memory, includeHidden: false) }),
              best.score >= config.suggestMin else { return nil }
        return try match(best.memory, score: best.score, source: .embedding)
    }

    /// Whether a match is strong enough to merge without asking "Which one?".
    public func isStrong(_ match: MemoryMatch) -> Bool {
        match.source == .extractor || (embedder?.suggestsOnItsOwn == true && match.score >= config.suggestMin)
    }

    /// "Which one?": the nearest few with no minimum; newest first when there are no vectors.
    public func picker(for text: String, excluding: Set<MemoryID>, includeHidden: Bool) throws -> [MemoryMatch] {
        let byScore = try scored(text, excluding: excluding).filter { pickable($0.memory, includeHidden: includeHidden) }
        if !byScore.isEmpty {
            return try byScore.prefix(config.pickerCount).map { try match($0.memory, score: $0.score, source: .embedding) }
        }
        let newest = try store.memories.allMemories()
            .filter { !excluding.contains($0.id) && pickable($0, includeHidden: includeHidden) }
            .sorted { $0.createdAt > $1.createdAt }
        return try newest.prefix(config.pickerCount).map { try match($0, score: 0, source: .embedding) }
    }

    /// True when the embedder's scores mean something on their own (M4.1 device finding).
    public var isCalibrated: Bool { embedder?.suggestsOnItsOwn == true }

    /// Every memory with a vector under the current model, for the duplicate pass (M5).
    public func embedded() throws -> [(memory: Memory, vector: [Float])] {
        guard let embedder else { return [] }
        return try store.embeddings.memoriesWithVectors(model: embedder.model)
    }

    // MARK: - Helpers

    private func eligible(_ memory: Memory, includeHidden: Bool) -> Bool {
        !memory.excludedFromAI && (includeHidden || !memory.hiddenFromTimeline)
    }

    /// The manual picker lists tellings the person can see; a resolver stand-in is not one.
    private func pickable(_ memory: Memory, includeHidden: Bool) -> Bool {
        eligible(memory, includeHidden: includeHidden) && !memory.isFloating
    }

    /// Every embedded memory scored against `text`, best first. Empty without an embedder or a vector.
    private func scored(_ text: String, excluding: Set<MemoryID>) throws -> [(memory: Memory, score: Float)] {
        guard let embedder, let probe = embedder.vector(for: text) else { return [] }
        return try store.embeddings.memoriesWithVectors(model: embedder.model)
            .filter { !excluding.contains($0.memory.id) }
            .map { (memory: $0.memory, score: Similarity.cosine(probe, $0.vector)) }
            .sorted { $0.score > $1.score }
    }

    private func match(_ memory: Memory, score: Float, source: MemoryMatch.Source) throws -> MemoryMatch {
        let span = try store.memories.spans(of: memory.id).first
        let session = try span.flatMap { try store.sessions.fetchSegment($0.segmentID) }.flatMap { try store.sessions.fetch($0.sessionID) }
        return MemoryMatch(memoryID: memory.id, title: memory.title, recordedAt: session?.startedAt, score: score, source: source)
    }
}
