import Foundation
import Testing
import GRDB
@testable import LifelineKit

private struct Env {
    let db: AppDatabase, sessions: SessionRepository, candidates: CandidateRepository, memories: MemoryRepository, people: PeopleRepository
    let session: SessionID, segment: Segment, candidate: Candidate
    init() throws {
        db = try AppDatabase.inMemory()
        sessions = SessionRepository(db); candidates = CandidateRepository(db); memories = MemoryRepository(db); people = PeopleRepository(db)
        (session, _) = try StoreFixtures.session(in: sessions)
        segment = try sessions.segments(in: session)[0]
        candidate = StoreFixtures.candidate(segment.id)
        try candidates.insert(candidate)
    }
    func span(_ memory: MemoryID) -> MemorySpan { MemorySpan(memoryID: memory, segmentID: segment.id, startMs: 0, endMs: 1_000, order: 0) }
}

@Test func memoryNeedsAtLeastOneSpan() throws {
    let env = try Env()
    let memory = StoreFixtures.memory(from: env.candidate.id)
    #expect(throws: MemoryRepository.Error.noSpan) { try env.memories.insert(memory, spans: [], people: [], places: [], anchors: []) }
    #expect(try env.memories.memories(in: env.session).isEmpty)
}

@Test func memoryInsertIsOneTransaction() throws {
    let env = try Env()
    let memory = StoreFixtures.memory(from: env.candidate.id)
    let ghost = MemoryPerson(memoryID: memory.id, personID: PersonID(), roleText: "my mother")
    #expect(throws: DatabaseError.self) {
        try env.memories.insert(memory, spans: [env.span(memory.id)], people: [ghost], places: [], anchors: [])
    }
    #expect(try env.memories.memories(in: env.session).isEmpty)
}

@Test func memoryRoundTripsWithPeoplePlacesAndAnchors() throws {
    let env = try Env()
    let maya = try env.people.insertPerson(displayName: "Maya")
    let place = try env.people.insertPlace(nameText: "Fresno")
    let memory = StoreFixtures.memory(from: env.candidate.id)
    let anchor = Anchor(id: .init(), memoryID: memory.id, phrase: "when I was six", relation: .age, targetKind: .none, targetID: nil, value: nil, resolved: false)
    try env.memories.insert(memory, spans: [env.span(memory.id)],
                            people: [MemoryPerson(memoryID: memory.id, personID: maya.id, roleText: "my sister")],
                            places: [MemoryPlace(memoryID: memory.id, placeID: place.id)], anchors: [anchor])
    #expect(try env.memories.memories(in: env.session).map(\.title) == ["The pomegranate tree"])
    #expect(try env.memories.people(of: memory.id).map(\.displayName) == ["Maya"])
    #expect(try env.memories.spans(of: memory.id).count == 1)
    #expect(try env.memories.anchors(of: memory.id).map(\.phrase) == ["when I was six"])
}

@Test func excludedSegmentIDsFollowSpans() throws {
    let db = try AppDatabase.inMemory()
    let sessions = SessionRepository(db), candidates = CandidateRepository(db), memories = MemoryRepository(db)
    let (session, segments) = try StoreFixtures.session(in: sessions, segments: ["one two", "three four", "five six"])
    let (other, otherSegments) = try StoreFixtures.session(in: sessions, segments: ["seven eight"])
    func tell(_ segment: Segment, excluded: Bool) throws {
        let candidate = StoreFixtures.candidate(segment.id)
        try candidates.insert(candidate)
        let memory = StoreFixtures.memory(from: candidate.id)
        let span = MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: 0, endMs: 1_000, order: 0)
        try memories.insert(memory, spans: [span], people: [], places: [], anchors: [])
        if excluded { try memories.setExcluded(memory.id, true) }
    }
    try tell(segments[0], excluded: true)
    try tell(segments[1], excluded: false)
    try tell(otherSegments[0], excluded: true)
    #expect(try memories.excludedSegmentIDs(in: session) == [segments[0].id])
    #expect(try memories.excludedSegmentIDs(in: other) == [otherSegments[0].id])
}

@Test func oneExcludedMemoryWithSpansInTwoSegmentsReturnsBoth() throws {
    let db = try AppDatabase.inMemory()
    let sessions = SessionRepository(db), candidates = CandidateRepository(db), memories = MemoryRepository(db)
    let (session, segments) = try StoreFixtures.session(in: sessions, segments: ["one two", "three four", "five six"])
    let candidate = StoreFixtures.candidate(segments[0].id)
    try candidates.insert(candidate)
    let memory = StoreFixtures.memory(from: candidate.id)
    let spans = [0, 2].enumerated().map { MemorySpan(memoryID: memory.id, segmentID: segments[$1].id, startMs: 0, endMs: 1_000, order: $0) }
    try memories.insert(memory, spans: spans, people: [], places: [], anchors: [])
    try memories.setExcluded(memory.id, true)
    #expect(try memories.excludedSegmentIDs(in: session) == [segments[0].id, segments[2].id])
}
