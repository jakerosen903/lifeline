import Foundation
import Testing
@testable import LifelineKit

private struct Env {
    let db: AppDatabase, store: ExtractionStore, chapters: ChapterRepository, session: SessionID, segment: Segment
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        chapters = ChapterRepository(db)
        (session, _) = try StoreFixtures.session(in: store.sessions)
        segment = try store.sessions.segments(in: session)[0]
    }
    func memory(_ title: String, range: TimeRange = .unplaced) throws -> Memory {
        let c = StoreFixtures.candidate(segment.id, ordinal: Int.random(in: 0..<100_000), payload: "{}")
        try store.candidates.insert(c)
        var m = StoreFixtures.memory(from: c.id, title: title)
        m.range = range
        try store.memories.insert(m, spans: [MemorySpan(memoryID: m.id, segmentID: segment.id, startMs: 0, endMs: 500, order: 0)], people: [], places: [], anchors: [])
        return m
    }
}

@Test func v4CreatesChapterCollectionCuriosityAndPromptLogTables() throws {
    let db = try AppDatabase.inMemory()
    let tables = try db.writer.read { try String.fetchAll($0, sql: "select name from sqlite_master where type = 'table'") }
    for t in ["chapter", "collection", "collection_memory", "curiosity_item", "prompt_log"] { #expect(tables.contains(t), "missing \(t)") }
}

@Test func memoryRangeColumnsRoundTripThroughTimeRange() throws {
    let env = try Env()
    let range = TimeRange.year(1998, origin: .inferred, evidence: "when I was twelve")
    let m = try env.memory("Yosemite", range: range)
    let fetched = try #require(try env.store.memories.fetch(m.id))
    #expect(fetched.range == range)
    let blank = try env.memory("Shelf")
    #expect(try env.store.memories.fetch(blank.id)?.range == .unplaced)
    #expect(try env.store.memories.unplacedMemories().map(\.title) == ["Shelf"])
    try env.store.memories.updateRange(blank.id, TimeRange.year(2001, origin: .stated, evidence: "in 2001"))
    #expect(try env.store.memories.fetch(blank.id)?.range.earliest?.year == 2001)
    #expect(try env.store.memories.allMemories().count == 2)
}

@Test func collectionSpanDerivesFromPlacedMembersOnly() throws {
    let env = try Env()
    let placed = try env.memory("Station wagon", range: .year(1998, origin: .stated, evidence: nil))
    let later = try env.memory("Mirror Lake", range: .year(2000, origin: .stated, evidence: nil))
    let unplaced = try env.memory("The bear")
    let trips = try env.chapters.insertCollection(titled: "Family trips to Yosemite")
    for m in [placed, later, unplaced] { try env.chapters.add(memory: m.id, to: trips.id) }
    try env.chapters.add(memory: placed.id, to: trips.id)
    #expect(try env.chapters.members(of: trips.id).count == 3)
    let span = try env.chapters.derivedSpan(of: trips.id)
    #expect(span.earliest?.iso == "1998-01-01" && span.latest?.iso == "2000-12-31" && span.origin == .derived)
    #expect(try env.chapters.collections(of: unplaced.id).map(\.title) == ["Family trips to Yosemite"])
    let empty = try env.chapters.insertCollection(titled: "Nothing yet")
    #expect(try env.chapters.derivedSpan(of: empty.id) == .unplaced)
}

@Test func insertCollectionReusesTitleIgnoringCase() throws {
    let env = try Env()
    let a = try env.chapters.insertCollection(titled: "Summers at the lake")
    let b = try env.chapters.insertCollection(titled: "summers at the lake ")
    #expect(a.id == b.id)
    #expect(try env.chapters.collections().count == 1)
}

@Test func chaptersKeepOrderAndRangeAndMembers() throws {
    let env = try Env()
    let childhood = try env.chapters.insertChapter(title: "Childhood")
    let college = try env.chapters.insertChapter(title: nil)
    #expect(try env.chapters.chapters().map(\.order) == [0, 1])
    try env.chapters.setRange(childhood.id, .year(1998, origin: .derived, evidence: nil))
    #expect(try env.chapters.chapters()[0].range.earliest?.year == 1998)
    let m = try env.memory("Yosemite")
    try env.chapters.assign(memory: m.id, toChapter: childhood.id)
    #expect(try env.store.memories.memories(inChapter: childhood.id).map(\.title) == ["Yosemite"])
    #expect(try env.store.memories.memories(inChapter: college.id).isEmpty)
    try env.chapters.assign(memory: m.id, toChapter: nil)
    #expect(try env.store.memories.memories(inChapter: childhood.id).isEmpty)
}

@Test func floatingMemoryHasNoCandidateAndASpan() throws {
    let env = try Env()
    let floating = try env.store.memories.insertFloating(title: "graduation", segment: env.segment.id, startMs: 100, endMs: 900)
    let fetched = try #require(try env.store.memories.fetch(floating.id))
    #expect(fetched.createdFromCandidateID == nil && fetched.range == .unplaced && fetched.isFloating)
    #expect(try env.store.memories.spans(of: floating.id).first?.startMs == 100)
}
