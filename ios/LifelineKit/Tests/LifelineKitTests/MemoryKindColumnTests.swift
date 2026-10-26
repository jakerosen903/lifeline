import Foundation
import GRDB
import Testing
@testable import LifelineKit

// M7, PR A: a memory's kind is a column; facts, feelings and goals are placed but hidden.

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }
private let seg = SegmentID()

private func ref(_ title: String, kind: MemoryKind = .event) -> MemoryRef {
    MemoryRef(id: MemoryID(), title: title, range: .unplaced, primarySpan: MemoryRef.Span(segmentID: seg, startMs: 0, endMs: 1_000), kind: kind)
}
private func anchor(_ memory: MemoryID, _ phrase: String, _ relation: AnchorRelation, target: String? = nil) -> Anchor {
    Anchor(id: .init(), memoryID: memory, phrase: phrase, relation: relation, targetKind: .none, targetID: nil,
           targetText: target, value: nil, resolved: false)
}

private struct Env {
    let store: ExtractionStore, actions: CandidateActions, segment: Segment
    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
        let (session, _) = try StoreFixtures.session(in: store.sessions, segments: ["we lived on Elm Street for years"])
        segment = try store.sessions.segments(in: session)[0]
    }

    func memory(_ title: String, range: TimeRange = .unplaced, chapter: ChapterID? = nil) throws -> Memory {
        let card = StoreFixtures.candidate(segment.id, ordinal: try store.memories.allMemories().count)
        try store.candidates.insert(card)
        let m = StoreFixtures.memory(from: card.id, title: title)
        try store.memories.insert(m, spans: [MemorySpan(memoryID: m.id, segmentID: segment.id, startMs: 0, endMs: 1000, order: 0)], people: [], places: [], anchors: [])
        if range.isPlaced { try store.memories.updateRange(m.id, range) }
        if let chapter { try store.chapters.assign(memory: m.id, toChapter: chapter) }
        return try #require(try store.memories.fetch(m.id))
    }
}

private func year(_ y: Int) -> TimeRange {
    TimeRange(earliest: d("\(y)-01-01"), latest: d("\(y)-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .stated, evidenceText: "in \(y)")
}

@Test func v9FillsKindFromPayloads() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v8")
    try queue.write { db in
        try db.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1)")
        try db.execute(sql: "insert into segment (id, session_id, \"index\", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 1000, 'hi', 'extracted')")
        let cards = [("cA", #"{"kind":"fact"}"#), ("cB", #"{"kind":"event"}"#), ("cC", #"{"title":"v1"}"#), ("cE", #"{"kind":"nonsense"}"#)]
        for (i, (id, payload)) in cards.enumerated() {
            try db.execute(sql: "insert into candidate (id, segment_id, extractor_version, ordinal, kind, payload, confidence, status, created_at) values (?, 'g1', 'v5', ?, 'memory', ?, 0.9, 'accepted', '2026-10-01')",
                           arguments: [id, i, payload])
        }
        for (m, c) in [("A", "cA"), ("B", "cB"), ("C", "cC"), ("E", "cE")] {
            try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_from_candidate_id, created_at) values (?, ?, 'q', 'timeline', ?, '2026-10-01')", arguments: [m, m, c])
        }
        try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_at) values ('D', 'D', 'q', 'timeline', '2026-10-01')")
    }
    try Migrations.migrator.migrate(queue)
    let kinds = try queue.read { db in
        Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "select id, kind from memory").map { ($0["id"] as String, $0["kind"] as String) })
    }
    #expect(kinds == ["A": "fact", "B": "event", "C": "event", "D": "event", "E": "event"])
}

@Test func keepWritesTheCardsKind() throws {
    let env = try Env()
    for (i, kind) in [MemoryKind.fact, .feeling, .goal, .event].enumerated() {
        let out = MemoryOut(ref: "m\(i)", kind: kind, title: "T\(i)", quote: "we lived", segmentSpan: WordSpan(startWord: 0, endWord: 2),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let card = StoreFixtures.candidate(env.segment.id, ordinal: i, payload: try CandidatePayload.encode(out))
        try env.store.candidates.insert(card)
        let kept = try env.actions.acceptMemory(card)
        #expect(try env.store.memories.fetch(kept.memory.id)?.kind == kind)
    }
    #expect(try env.store.memories.aboutMemories(includingHidden: false).map(\.title) == ["T0", "T1", "T2"])
}

@Test func factIsPlacedButAsksNothing() {
    let fact = ref("We lived in Lisbon", kind: .fact)
    let out = Resolver.resolve(ResolverInput(memories: [fact],
                                             anchors: [anchor(fact.id, "in 1990", .absolute), anchor(fact.id, "after the wedding", .after, target: "the wedding")],
                                             birthDate: nil, chapters: []))
    #expect(out.placements[fact.id]?.earliest?.year == 1990, "a fact is still placed and its range stored")
    #expect(out.curiosity.isEmpty, "no unresolved-anchor question is made about a fact")
    var placed = fact
    placed.range = out.placements[fact.id]!
    placed.range.origin = .inferred
    #expect(RelativeQuestions.question(for: placed, anchors: [], placed: [], siblings: [placed], birthDate: nil, config: .default) == nil)
}

@Test func factStillPlacesItsDependants() {
    let fact = ref("Moved to Lisbon", kind: .fact)
    let event = ref("The first winter")
    let out = Resolver.resolve(ResolverInput(memories: [fact, event],
                                             anchors: [anchor(fact.id, "in 1990", .absolute), anchor(event.id, "after we moved to Lisbon", .after, target: "Moved to Lisbon")],
                                             birthDate: nil, chapters: []))
    #expect(out.placements[event.id]?.isPlaced == true, "a moment anchored on a fact still places")
}

@Test func kindChangeRecomputesChapterRange() throws {
    let env = try Env()
    let chapter = try env.store.chapters.insertChapter(title: "Lisbon")
    _ = try env.memory("Early", range: year(1995), chapter: chapter.id)
    let late = try env.memory("Late", range: year(2001), chapter: chapter.id)
    try env.actions.chapterRangeFromMembers(chapter.id)
    #expect(try env.store.chapters.chapter(id: chapter.id)?.range.latest?.year == 2001)

    try env.actions.setKind(late.id, .fact)
    #expect(try env.store.chapters.chapter(id: chapter.id)?.range.latest?.year == 1995, "a fact leaves the chapter's range")
    #expect(try env.store.memories.fetch(late.id)?.chapterID == chapter.id, "it keeps its chapter_id")
    #expect(try env.store.memories.fetch(late.id)?.range.latest?.year == 2001, "its own range is still stored")
    #expect(try env.store.memories.aboutMemories(includingHidden: false).map(\.id) == [late.id])
    #expect(try env.store.memories.moments(inChapter: chapter.id).map(\.title) == ["Early"])

    try env.actions.setKind(late.id, .event)
    #expect(try env.store.chapters.chapter(id: chapter.id)?.range.latest?.year == 2001, "a moment again, it counts again")
    #expect(try env.store.memories.aboutMemories(includingHidden: false).isEmpty)
}

@Test func kindChangeRetiresAndRestoresCuriosity() throws {
    let env = try Env()
    let m = try env.memory("The garden")
    try env.store.memories.insertAnchor(anchor(m.id, "after graduation", .after, target: "graduation"))
    _ = try ResolverRunner(store: env.store).run()
    #expect(try env.store.curiosity.open().contains { $0.sourceMemoryID == m.id })

    try env.actions.setKind(m.id, .feeling)
    #expect(try !env.store.curiosity.open().contains { $0.sourceMemoryID == m.id }, "no question about a feeling")

    try env.actions.setKind(m.id, .event)
    #expect(try env.store.curiosity.open().contains { $0.sourceMemoryID == m.id }, "the question comes back with the moment")
}
