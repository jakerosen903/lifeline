import Foundation
import Testing
@testable import LifelineKit

/// Hand-set vectors keyed by the exact text `MemoryMatcher.text(title:quote:)` builds.
struct FakeEmbedder: SentenceEmbedder {
    let model = "fake"
    var table: [String: [Float]]
    func vector(for text: String) -> [Float]? { table[text] }
}

private struct MatchEnv {
    let store: ExtractionStore
    var memories: [String: Memory] = [:]
    var table: [String: [Float]] = [:]

    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
    }

    /// One memory per session so `recordedAt` differs; vector keyed by the matcher's text.
    mutating func memory(_ title: String, quote: String, vector: [Float], excluded: Bool = false, hidden: Bool = false) throws -> Memory {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [quote])
        let c = StoreFixtures.candidate(segs[0].id)
        try store.candidates.insert(c)
        var m = StoreFixtures.memory(from: c.id, title: title)
        m.summaryQuote = quote
        m.excludedFromAI = excluded
        m.hiddenFromTimeline = hidden
        try store.memories.insert(m, spans: [MemorySpan(memoryID: m.id, segmentID: segs[0].id, startMs: 0, endMs: 500, order: 0)], people: [], places: [], anchors: [])
        memories[title] = m
        table[MemoryMatcher.text(title: title, quote: quote)] = vector
        return m
    }

    func matcher(_ embedder: (any SentenceEmbedder)?) -> MemoryMatcher {
        MemoryMatcher(store: store, embedder: embedder)
    }
}

private func card(_ title: String, quote: String) -> MemoryOut {
    MemoryOut(ref: "m1", kind: .event, title: title, quote: quote, segmentSpan: WordSpan(startWord: 0, endWord: 0),
              peopleRefs: [], placeText: nil, anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
}

@Test func cosineOfIdenticalIsOneAndOrthogonalIsZero() {
    #expect(Similarity.cosine([1, 0], [1, 0]) == 1)
    #expect(Similarity.cosine([1, 0], [0, 1]) == 0)
    #expect(Similarity.cosine([0, 0], [1, 0]) == 0)
    #expect(Similarity.cosine([1, 0, 0], [1, 0]) == 0, "mismatched lengths never match")
    #expect(abs(Similarity.cosine([0.7, 0.7, 0], [1, 0, 0]) - 0.7071) < 0.001)
}

@Test func relatedReturnsNearestAboveThresholdAndSkipsExcluded() throws {
    var env = try MatchEnv()
    let a = try env.memory("orange house", quote: "we lived in an orange house", vector: [1, 0, 0])
    let b = try env.memory("canal", quote: "right on the canal", vector: [0.7, 0.7, 0])
    _ = try env.memory("disney", quote: "we drove to disney", vector: [0, 0, 1])
    _ = try env.memory("secret", quote: "never tell the model", vector: [1, 0, 0], excluded: true)
    env.table["the orange house again"] = [1, 0, 0]
    let matcher = env.matcher(FakeEmbedder(table: env.table))
    for m in env.memories.values { try matcher.index(m) }
    #expect(try env.store.embeddings.memoryIDsWithRows().count == 3, "an excluded memory gets no row")
    let related = try matcher.related(to: "the orange house again")
    #expect(related.map(\.id) == [a.id, b.id])
    #expect(try matcher.related(to: "the orange house again", excluding: [a.id]).map(\.id) == [b.id])
    #expect(try matcher.related(to: "unknown text").isEmpty, "no vector, nothing related")
}

@Test func suggestionPrefersExtractorThenStrongEmbedding() throws {
    var env = try MatchEnv()
    let a = try env.memory("orange house", quote: "we lived in an orange house", vector: [1, 0, 0])
    let b = try env.memory("canal", quote: "right on the canal", vector: [0.7, 0.7, 0])
    let retold = card("The orange house", quote: "grew up in an orange house")
    env.table[MemoryMatcher.text(title: retold.title, quote: retold.quote)] = [1, 0, 0]
    let matcher = env.matcher(FakeEmbedder(table: env.table))
    for m in env.memories.values { try matcher.index(m) }

    let fromExtractor = try #require(try matcher.suggestion(for: retold, extractorSameAs: b.id))
    #expect(fromExtractor.memoryID == b.id && fromExtractor.source == .extractor && fromExtractor.title == "canal")
    #expect(fromExtractor.recordedAt != nil)

    let fromVectors = try #require(try matcher.suggestion(for: retold, extractorSameAs: nil))
    #expect(fromVectors.memoryID == a.id && fromVectors.source == .embedding && abs(fromVectors.score - 1) < 0.001)

    let canalOnly = card("The canal", quote: "the canal again")
    env.table[MemoryMatcher.text(title: canalOnly.title, quote: canalOnly.quote)] = [0, 1, 0]   // cos with b = .707, below 0.80
    let weak = env.matcher(FakeEmbedder(table: env.table))
    #expect(try weak.suggestion(for: canalOnly, extractorSameAs: nil) == nil)

    #expect(try matcher.suggestion(for: retold, extractorSameAs: MemoryID(rawValue: "nope"))?.memoryID == a.id, "an unknown extractor id falls through to vectors")

    try env.store.memories.setHidden(a.id, true)
    #expect(try matcher.suggestion(for: retold, extractorSameAs: nil) == nil, "a hidden memory is never suggested on a card")
    #expect(try matcher.suggestion(for: retold, extractorSameAs: a.id) == nil, "not even when the extractor names it")
    let text = MemoryMatcher.text(title: retold.title, quote: retold.quote)
    #expect(try matcher.picker(for: text, excluding: [], includeHidden: false).map(\.memoryID) == [b.id])
    #expect(try matcher.picker(for: text, excluding: [], includeHidden: true).map(\.memoryID) == [a.id, b.id])
    #expect(try matcher.picker(for: text, excluding: [b.id], includeHidden: true).map(\.memoryID) == [a.id])
}

@Test func aNilEmbedderWritesNothingAndSuggestsNothing() throws {
    var env = try MatchEnv()
    let a = try env.memory("orange house", quote: "we lived in an orange house", vector: [1, 0, 0])
    _ = try env.memory("canal", quote: "right on the canal", vector: [0.7, 0.7, 0])
    let matcher = env.matcher(nil)
    try matcher.index(a)
    #expect(try env.store.embeddings.memoryIDsWithRows().isEmpty)
    #expect(try matcher.backfill() == 0)
    #expect(try matcher.related(to: "anything").isEmpty)
    let retold = card("The orange house", quote: "grew up in an orange house")
    #expect(try matcher.suggestion(for: retold, extractorSameAs: nil) == nil)
    #expect(try matcher.suggestion(for: retold, extractorSameAs: a.id)?.memoryID == a.id, "the extractor path needs no vectors")
    let picker = try matcher.picker(for: "anything", excluding: [], includeHidden: false)
    #expect(picker.count == 2 && picker[0].title == "canal", "with no vectors the picker lists the newest memories first")
}

@Test func backfillIndexesOnlyMemoriesWithoutRows() throws {
    var env = try MatchEnv()
    let a = try env.memory("a", quote: "aa", vector: [1, 0])
    _ = try env.memory("b", quote: "bb", vector: [0, 1])
    _ = try env.memory("c", quote: "cc", vector: [1, 1])
    let matcher = env.matcher(FakeEmbedder(table: env.table))
    try matcher.index(a)
    #expect(try matcher.backfill() == 2)
    #expect(try matcher.backfill() == 0)
    #expect(try env.store.embeddings.memoryIDsWithRows().count == 3)
}

@Test func hashingEmbedderScoresWordOverlap() {
    let e = HashingEmbedder()
    let a = e.vector(for: "the house had a blue door")!
    let b = e.vector(for: "The house had a BLUE door!")!
    let c = e.vector(for: "we drove to disney in the wagon")!
    #expect(a.count == HashingEmbedder.dimensions && Similarity.cosine(a, b) > 0.999, "case and punctuation do not matter")
    #expect(Similarity.cosine(a, c) < 0.5)
    #expect(e.vector(for: "   ") == nil)
    #expect(e.vector(for: "blue door") == HashingEmbedder().vector(for: "blue door"), "deterministic across instances")
}
