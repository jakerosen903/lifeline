import Foundation
import Testing
@testable import LifelineKit

// Chapters, Task 2: nothing writes a member span to a chapter. `chapter.range` holds stated years only.

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

    func range(of chapter: ChapterID) throws -> TimeRange? { try store.chapters.chapter(id: chapter)?.range }
}

@Test func assigningAMemberDoesNotDateTheChapter() throws {
    let env = try Env()
    let m = try env.memory("Painting the fence", range: .stated(year: 1998))
    let chapter = try env.actions.createChapter(title: "Elm Street", containing: m.id)
    #expect(try env.range(of: chapter.id) == .unplaced)
}

@Test func aStatedRangeSurvivesAMemberThatMoves() throws {
    let env = try Env()
    let chapter = try env.store.chapters.insertChapter(title: "Elm Street")
    let stated = TimeRange.stated(between: 2008, and: 2012)
    try env.store.chapters.setRange(chapter.id, stated)
    let m = try env.memory("Painting the fence", range: .stated(year: 1990))
    try env.actions.assign(memory: m.id, toChapter: chapter.id)
    try env.store.memories.updateRange(m.id, .stated(year: 2020))
    _ = try ResolverRunner(store: env.store).run()
    #expect(try env.range(of: chapter.id) == stated)
}

@Test func aKindChangeDoesNotTouchTheChaptersRange() throws {
    let env = try Env()
    let chapter = try env.store.chapters.insertChapter(title: "Elm Street")
    let stated = TimeRange.stated(between: 2008, and: 2012)
    try env.store.chapters.setRange(chapter.id, stated)
    let m = try env.memory("Painting the fence", range: .stated(year: 2009), chapter: chapter.id)
    try env.actions.setKind(m.id, .fact)
    #expect(try env.range(of: chapter.id) == stated)
    try env.actions.setKind(m.id, .event)
    #expect(try env.range(of: chapter.id) == stated)
}

@Test func aMergeDoesNotTouchTheChaptersRange() throws {
    let env = try Env()
    let chapter = try env.store.chapters.insertChapter(title: "Childhood")
    let stated = TimeRange.stated(between: 1985, and: 1995)
    try env.store.chapters.setRange(chapter.id, stated)
    let target = try env.memory("Orange house", range: .stated(year: 1990), chapter: chapter.id)
    let source = try env.memory("The drive", range: .stated(year: 1998))
    _ = try env.actions.merge(source.id, into: target.id)
    #expect(try env.range(of: chapter.id) == stated)
}

@Test func thePruneKeepsAnUntitledChapterWithStatedYears() throws {
    let env = try Env()
    let chapter = try env.store.chapters.insertChapter(title: nil)
    try env.store.chapters.setRange(chapter.id, .stated(year: 2001))
    #expect(try env.store.chapters.deleteEmptyUntitled() == 0)
    #expect(try env.store.chapters.chapter(id: chapter.id) != nil)
}

@Test func thePruneStillRemovesAnUntitledChapterWithADerivedRange() throws {
    let env = try Env()
    let chapter = try env.store.chapters.insertChapter(title: nil)
    try env.store.chapters.setRange(chapter.id, .year(2001, origin: .derived, evidence: nil))
    #expect(try env.store.chapters.deleteEmptyUntitled() == 1)
}

@Test func theContextPacketSendsStatedYearsOnly() {
    let derived = Chapter(id: .init(), title: "Boston", range: .year(2011, origin: .derived, evidence: nil), order: 0)
    let stated = Chapter(id: .init(), title: "Austin", range: .stated(year: 2011), order: 1)
    let segment = Segment(id: .init(), sessionID: SessionID(rawValue: "s"), index: 0, startMs: 0, endMs: 1, text: "x", status: .pending)
    let packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open", chapters: [derived, stated])
    #expect(packet.chapters.map { $0.rangeText } == [nil, "2011"])
}
