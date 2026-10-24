import Foundation
import Testing
@testable import LifelineKit

@Test func duplicatePassWritesVerdicts() async throws {
    var env = try PairEnv()
    let door1 = try env.memory("The blue door", vector: [1, 0, 0])
    let door2 = try env.memory("The blue door", vector: [1, 0, 0])
    let maya = try env.memory("Maya climbed it", vector: [0.8, 0.6, 0])
    let canal = try env.memory("The canal", vector: [0.7, 0.7, 0])
    let matcher = env.matcher()
    try env.indexAll(matcher)
    let log = LogCollector()
    let pass = DuplicatePass(store: env.store, matcher: matcher, reconcile: ScriptedReconcileService(), actions: CandidateActions(store: env.store), log: { log.append($0) })
    let finished = LogCollector()
    await pass.setOnFinished { finished.append("\($0)") }
    let judged = await pass.run()
    #expect(finished.all == ["\(judged)"], "the screen hears about the new pairs")
    let rows = try env.store.pairs.pairs(touching: door1.id) + env.store.pairs.pairs(touching: door2.id) + env.store.pairs.pairs(touching: canal.id)
    let unique = Dictionary(grouping: rows, by: \.id).values.compactMap(\.first)
    #expect(judged == unique.count && judged > 0)
    let sameMoment = unique.filter { $0.verdict == .sameMoment }
    #expect(sameMoment.count == 1 && sameMoment[0].status == .open && sameMoment[0].key == PairKey(door1.id, door2.id))
    let sameStory = unique.filter { $0.verdict == .sameStory }
    #expect(sameStory.count == 2 && sameStory.allSatisfy { $0.status == .open && ($0.aMemoryID == maya.id || $0.bMemoryID == maya.id) })
    #expect(unique.filter { $0.verdict == .different }.allSatisfy { $0.status == .separate && $0.decidedAt != nil })
    #expect(try env.store.pairs.open(limit: 10).count == 3)
    #expect(log.all.contains { $0.contains("[duplicates]") })
    #expect(await pass.run() == 0, "every pair is on file now")
}

@Test func duplicatePassStopsQuietlyWithoutAKey() async throws {
    var env = try PairEnv()
    _ = try env.memory("The blue door", vector: [1, 0])
    _ = try env.memory("The blue door", vector: [1, 0])
    let matcher = env.matcher()
    try env.indexAll(matcher)
    let noKey = AnthropicReconcileService(config: .default, apiKey: { nil }, transport: FakeHTTPTransport([]))
    let pass = DuplicatePass(store: env.store, matcher: matcher, reconcile: noKey, actions: CandidateActions(store: env.store), log: { _ in })
    #expect(await pass.run() == 0)
    #expect(try env.store.pairs.open(limit: 10).isEmpty && (try env.store.pairs.known()).isEmpty)
}

/// The UI-test wiring end to end: word-overlap vectors, two cards kept with the same words,
/// the scripted reconciler, one open pair.
@Test func duplicatePassFindsTwoKeptBlueDoorsUnderTheHashingEmbedder() async throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    let matcher = MemoryMatcher(store: store, embedder: HashingEmbedder())
    let actions = CandidateActions(store: store, matcher: matcher)
    for _ in 0..<2 {
        let text = "the house had a blue door when I was six before Maya climbed it"
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        let out = MemoryOut(ref: "m1", kind: .event, title: "The blue door", quote: text, segmentSpan: WordSpan(startWord: 0, endWord: 13), peopleRefs: [], placeText: nil,
                            anchors: [], storyRef: UUID().uuidString, collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        _ = try actions.acceptMemory(c)
    }
    let log = LogCollector()
    let pass = DuplicatePass(store: store, matcher: matcher, reconcile: ScriptedReconcileService(), actions: actions, log: { log.append($0) })
    let judged = await pass.run()
    #expect(judged == 1, "\(log.all)")
    let open = try store.pairs.open(limit: 3)
    #expect(open.count == 1 && open.first?.verdict == .sameMoment)
}
