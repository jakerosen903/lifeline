import Foundation
import GRDB
import Testing
@testable import LifelineKit

// S3, Task 1: the You portrait reads in a fixed number of queries.

private func at(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 60) }

private final class StatementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// A store with the owner Jordan and one session (1 March 2026) of many segments.
private struct Fixture {
    let db: AppDatabase
    let store: ExtractionStore
    let session: Session
    let segments: [Segment]
    private var next = 0

    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        let session = Session(id: .init(), startedAt: Date(timeIntervalSince1970: 1_772_323_200), endedAt: nil, audioPath: "s1.m4a", stageLog: "[]", landingChoiceMade: false)
        self.session = session
        try store.sessions.insert(session)
        let sessions = store.sessions
        segments = try (0..<120).map { i in
            let segment = Segment(id: .init(), sessionID: session.id, index: i, startMs: i * 1_000, endMs: i * 1_000 + 900, text: "words \(i)", status: .pending)
            try sessions.insert(segment, words: [])
            return segment
        }
        try store.profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: "Dayton", freeText: nil, updatedAt: .now))
    }

    /// A told memory of a kind with spans (start, end) in order, the first in its own segment.
    mutating func memory(_ title: String, kind: MemoryKind, spans: [(Int, Int)] = [(0, 1_000)], hidden: Bool = false) throws -> Memory {
        next += 1
        let segment = segments[next]
        let candidate = StoreFixtures.candidate(segment.id)
        try store.candidates.insert(candidate)
        var memory = StoreFixtures.memory(from: candidate.id, title: title)
        memory.createdAt = at(next)
        try store.memories.insert(memory, spans: spans.enumerated().map { MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: $1.0, endMs: $1.1, order: $0) },
                                  people: [], places: [], anchors: [])
        if kind != .event { try store.memories.setKind(memory.id, kind) }
        if hidden { try store.memories.setHidden(memory.id, true) }
        return memory
    }

    mutating func floating(_ title: String, kind: MemoryKind) throws -> Memory {
        let made = try memory(title, kind: kind)
        try db.writer.write { try $0.execute(sql: "update memory set created_from_candidate_id = null where id = ?", arguments: [made.id.rawValue]) }
        return made
    }

    func entity(_ type: EntityType, _ title: String) throws -> Entity { try store.entities.insert(type: type, title: title) }
    func link(_ memory: Memory, _ entity: Entity, _ relation: EntityRelation) throws { try store.entities.link(memory.id, entity.id, relation: relation) }
}

@Test func firstTellingsReadTheLowestSpanWithItsSession() throws {
    var f = try Fixture()
    let f1 = try f.memory("Oldest of two", kind: .fact, spans: [(2_000, 6_000), (9_000, 12_000)])
    let event = try f.memory("The lake", kind: .event)
    let tellings = try f.store.memories.firstTellings(kinds: [.fact, .feeling, .goal])
    #expect(tellings[f1.id] == Telling(sessionID: f.session.id, audioPath: f.session.audioPath, range: MsRange(start: 2_000, end: 6_000), toldAt: f.session.startedAt))
    #expect(tellings[event.id] == nil, "a moment is not asked for")
}

@Test func ideaTellingsReadTheFirstEntitySpan() throws {
    var f = try Fixture()
    _ = try f.memory("x", kind: .fact)
    let yes = try f.entity(.idea, "Saying yes to things"), quiet = try f.entity(.idea, "Keeping quiet")
    try f.store.entities.insertSpan(EntitySpan(entityID: yes.id, segmentID: f.segments[5].id, startMs: 4_000, endMs: 5_000, order: 1))
    try f.store.entities.insertSpan(EntitySpan(entityID: yes.id, segmentID: f.segments[4].id, startMs: 0, endMs: 3_000, order: 0))
    let tellings = try f.store.entities.firstTellings(type: .idea)
    #expect(tellings[yes.id]?.range == MsRange(start: 0, end: 3_000))
    #expect(tellings[yes.id]?.sessionID == f.session.id)
    #expect(tellings[quiet.id] == nil, "an idea with no span has no telling")
}

@Test func aboutLinksListDetailBeforeMentionAndKeepHiddenEntities() throws {
    var f = try Fixture()
    let e1 = try f.memory("Lake feeling", kind: .feeling), f2 = try f.memory("The brave one", kind: .fact), g1 = try f.memory("Hope", kind: .goal)
    let event = try f.memory("Moment", kind: .event)
    let lake = try f.entity(.place, "The lake"), alder = try f.entity(.place, "Alder Street"), maya = try f.entity(.person, "Maya")
    try f.link(e1, alder, .mention)
    try f.link(e1, lake, .detail)
    try f.link(f2, maya, .detail)
    try f.link(event, lake, .mention)
    try f.store.entities.setHidden(maya.id, true)
    let links = try f.store.entities.aboutLinks(kinds: [.fact, .feeling, .goal])
    #expect(links[e1.id]?.map { "\($0.relation.rawValue) \($0.entity.title)" } == ["detail The lake", "mention Alder Street"])
    #expect(links[f2.id]?.first?.entity.hiddenFromTimeline == true)
    #expect(links[g1.id] == nil)
    #expect(links[event.id] == nil, "a moment is not asked for")
}

@Test func tagsByElementReadsEveryMemoryTagAtOnce() throws {
    var f = try Fixture()
    let f1 = try f.memory("Oldest of two", kind: .fact)
    try f.store.tags.tag(.memory, f1.id.rawValue, "work")
    try f.store.tags.tag(.memory, f1.id.rawValue, "Family")
    try f.store.tags.tag(.entity, f1.id.rawValue, "Elsewhere")
    #expect(try f.store.tags.tagsByElement(.memory)[f1.id.rawValue] == ["Family", "work"])
}

@Test func thePortraitSourceLeavesOutHiddenAndFloatingMemories() throws {
    var f = try Fixture()
    let f1 = try f.memory("Oldest of two", kind: .fact), f3 = try f.memory("Hidden fact", kind: .fact, hidden: true)
    let stand = try f.floating("Stand-in", kind: .fact)
    let event = try f.memory("A day", kind: .event)
    let owner = try #require(try f.store.profile.owner())
    try f.link(event, try #require(try f.store.entities.entity(id: owner.entityID)), .mention)
    let source = try f.store.portraitSource()
    #expect(source.aboutMemories.map(\.id) == [f1.id])
    #expect(!source.aboutMemories.contains { $0.id == f3.id || $0.id == stand.id })
    #expect(source.memoryTellings[f3.id] == nil && source.memoryTellings[stand.id] == nil)
    #expect(source.ownerMoments.map(\.id) == [event.id])
    #expect(source.profile?.birthPlaceText == "Dayton" && source.owner?.title == "Jordan")
}

@Test func thePortraitReadsInAFixedNumberOfStatements() throws {
    var f = try Fixture()
    let counter = StatementCounter()
    try f.db.writer.write { db in db.trace { _ in counter.add() } }
    let maya = try f.entity(.person, "Maya")

    func addLines(_ kind: MemoryKind, _ count: Int) throws {
        for i in 0..<count {
            let m = try f.memory("\(kind.rawValue) \(i)", kind: kind)
            try f.store.tags.tag(.memory, m.id.rawValue, "Family")
            try f.link(m, maya, .detail)
        }
    }
    func statementsForOneRead() throws -> Int {
        let before = counter.count
        _ = try f.store.portraitSource()
        return counter.count - before
    }
    try addLines(.fact, 3)
    let few = try statementsForOneRead()
    try addLines(.fact, 30); try addLines(.feeling, 10); try addLines(.goal, 10)
    // Heavy sessions are read at once too: one by a flag row, one by its stage log.
    for i in 0..<5 {
        let heavy = Session(id: .init(), startedAt: at(200 + i), endedAt: nil, audioPath: "h\(i).m4a", stageLog: i.isMultiple(of: 2) ? "[]" : wantsToStopLog, landingChoiceMade: true)
        try f.store.sessions.insert(heavy)
        let segment = Segment(id: .init(), sessionID: heavy.id, index: 0, startMs: 0, endMs: 900, text: "hard", status: .extracted)
        try f.store.sessions.insert(segment, words: [])
        if i.isMultiple(of: 2) { try f.store.candidates.insert(try flagRow(segment.id, Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false))) }
    }
    for i in 0..<10 {
        let idea = try f.entity(.idea, "Idea \(i)")
        try f.store.entities.insertSpan(EntitySpan(entityID: idea.id, segmentID: f.segments[100 + i].id, startMs: 0, endMs: 1_000, order: 0))
    }
    let many = try statementsForOneRead()
    #expect(try f.store.sessions.heavySessionIDs().count == 5)
    #expect(few == 66, "was \(few): the portrait's fixed number of statements, heavy sessions included")
    #expect(many == few)
}

// Final review, item 1: which sessions were heavy, read at once from stored flag rows and stage logs.

private let wantsToStopLog = #"[{"stage":"windDown","at":"2026-03-01T00:00:00Z","reason":"wantsToStop"}]"#

private func flagRow(_ segment: SegmentID, _ flags: Flags) throws -> Candidate {
    StoreFixtures.candidate(segment, ordinal: 0, kind: .flag, payload: try CandidatePayload.encode(flags))
}

@Test func heavySessionsAreReadFromFlagRowsAndStageLogs() throws {
    let f = try Fixture()
    func session(_ log: String) throws -> (Session, Segment) {
        let s = Session(id: .init(), startedAt: at(300), endedAt: nil, audioPath: "x.m4a", stageLog: log, landingChoiceMade: true)
        try f.store.sessions.insert(s)
        let segment = Segment(id: .init(), sessionID: s.id, index: 0, startMs: 0, endMs: 900, text: "words", status: .extracted)
        try f.store.sessions.insert(segment, words: [])
        return (s, segment)
    }
    let (flagged, flaggedSegment) = try session("[]")
    try f.store.candidates.insert(try flagRow(flaggedSegment.id, Flags(disclosure: .present, wantsToStop: false, wantsToChangeSubject: false)))
    let (stopped, _) = try session(wantsToStopLog)
    let (onlySubject, subjectSegment) = try session("[]")
    try f.store.candidates.insert(try flagRow(subjectSegment.id, Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: true)))
    let heavy = try f.store.sessions.heavySessionIDs()
    #expect(heavy == [flagged.id, stopped.id])
    #expect(!heavy.contains(onlySubject.id) && !heavy.contains(f.session.id), "a change of subject is not heavy")
    #expect(try f.store.portraitSource().heavySessions == heavy)
}
