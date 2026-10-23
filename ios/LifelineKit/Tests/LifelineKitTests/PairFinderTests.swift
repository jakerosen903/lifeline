import Foundation
import Testing
@testable import LifelineKit

/// Memories with hand-made vectors, one per session so ages differ.
struct PairEnv {
    let store: ExtractionStore
    var table: [String: [Float]] = [:]
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    init() throws { store = ExtractionStore(try AppDatabase.inMemory()) }

    @discardableResult
    mutating func memory(_ title: String, vector: [Float], hidden: Bool = false, excluded: Bool = false) throws -> Memory {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [title.lowercased()])
        clock.addTimeInterval(60)
        var m = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segs[0].id, title: title, createdAt: clock)
        m.summaryQuote = title.lowercased()
        try store.memories.updateFields(m.id, title: m.title, summaryQuote: m.summaryQuote, createdFromCandidateID: m.createdFromCandidateID)
        if hidden { try store.memories.setHidden(m.id, true); m.hiddenFromTimeline = true }
        if excluded { try store.memories.setExcluded(m.id, true); m.excludedFromAI = true }
        table[MemoryMatcher.text(title: title, quote: title.lowercased())] = vector
        return m
    }

    mutating func standIn(_ title: String, vector: [Float]) throws -> Memory {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [title])
        let m = try store.memories.insertFloating(title: title, segment: segs[0].id, startMs: 0, endMs: 100)
        table[MemoryMatcher.text(title: title, quote: title)] = vector
        return m
    }

    func matcher(calibrated: Bool = true) -> MemoryMatcher {
        MemoryMatcher(store: store, embedder: FakeEmbedder(table: table, suggestsOnItsOwn: calibrated))
    }

    func indexAll(_ matcher: MemoryMatcher) throws {
        for m in try store.memories.allMemories() { try matcher.index(m) }
    }
}

@Test func pairFinderSkipsDecidedHiddenExcludedAndStandIns() throws {
    var env = try PairEnv()
    let a = try env.memory("Orange house", vector: [1, 0])
    let hidden = try env.memory("Hidden house", vector: [1, 0], hidden: true)
    let secret = try env.memory("Secret house", vector: [1, 0], excluded: true)
    let b = try env.memory("Orange house again", vector: [0.9, 0.1])
    let far = try env.memory("Disney", vector: [0, 1])
    let c = try env.memory("The orange house", vector: [0.8, 0.2])
    let floating = try env.standIn("graduation", vector: [1, 0])
    let matcher = env.matcher()
    try env.indexAll(matcher)
    try env.store.pairs.insert(DuplicatePair(id: .init(), aMemoryID: a.id, bMemoryID: b.id, score: 0.9, verdict: .sameMoment, status: .separate, decidedAt: .now))
    let found = try PairFinder(store: env.store, matcher: matcher).candidates()
    let keys = Set(found.map { PairKey($0.a.id, $0.b.id) })
    #expect(keys == [PairKey(a.id, c.id), PairKey(b.id, c.id)])
    for pair in found {
        #expect(pair.a.createdAt < pair.b.createdAt, "the older memory is a")
        #expect(![hidden.id, secret.id, far.id, floating.id].contains(pair.a.id) && ![hidden.id, secret.id, far.id, floating.id].contains(pair.b.id))
    }
    #expect(found.map(\.score) == found.map(\.score).sorted(by: >), "best first")
}

@Test func pairFinderAppliesTheFloorOnlyWhenCalibrated() throws {
    var env = try PairEnv()
    let a = try env.memory("Orange house", vector: [1, 0])
    let far = try env.memory("Disney", vector: [0, 1])
    let calibrated = env.matcher(calibrated: true)
    try env.indexAll(calibrated)
    #expect(try PairFinder(store: env.store, matcher: calibrated).candidates().isEmpty)
    let raw = env.matcher(calibrated: false)
    try env.indexAll(raw)
    let found = try PairFinder(store: env.store, matcher: raw).candidates()
    #expect(found.map { PairKey($0.a.id, $0.b.id) } == [PairKey(a.id, far.id)], "an uncalibrated model sends its top neighbours to the reconciler regardless")
}
