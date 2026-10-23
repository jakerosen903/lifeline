import Foundation
import Testing
@testable import LifelineKit

@Test func sameSegmentAndVersionTwiceIsRejected() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db); let repo = CandidateRepository(db)
    let (_, segs) = try StoreFixtures.session(in: sessions)
    try repo.insert(StoreFixtures.candidate(segs[0].id, ordinal: 0))
    #expect(throws: CandidateRepository.Error.duplicate) { try repo.insert(StoreFixtures.candidate(segs[0].id, ordinal: 0)) }
    #expect(try repo.candidates(for: segs[0].id).count == 1)
}

@Test func pendingCandidatesComeInSegmentThenOrdinalOrder() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db); let repo = CandidateRepository(db)
    let (session, segs) = try StoreFixtures.session(in: sessions, segments: ["one two three", "four five six"])
    try repo.insert(StoreFixtures.candidate(segs[1].id, ordinal: 1, payload: "s1#1"))
    try repo.insert(StoreFixtures.candidate(segs[0].id, ordinal: 1, payload: "s0#1"))
    try repo.insert(StoreFixtures.candidate(segs[1].id, ordinal: 0, payload: "s1#0"))
    try repo.insert(StoreFixtures.candidate(segs[0].id, ordinal: 0, payload: "s0#0"))
    #expect(try repo.pending(in: session).map(\.payload) == ["s0#0", "s0#1", "s1#0", "s1#1"])
}

@Test func setStatusRecordsARejection() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db); let repo = CandidateRepository(db)
    let (session, segs) = try StoreFixtures.session(in: sessions)
    let c = StoreFixtures.candidate(segs[0].id)
    try repo.insert(c)
    try repo.setStatus(c.id, .dismissed, rejection: "quote not in segment")
    let stored = try #require(try repo.fetch(c.id))
    #expect(stored.status == .dismissed && stored.rejection == "quote not in segment")
    #expect(try repo.pending(in: session).isEmpty)
}

@Test func batchInsertIsAllOrNothingAndSetsTheSegmentStatus() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db); let repo = CandidateRepository(db)
    let (_, segs) = try StoreFixtures.session(in: sessions)
    let a = StoreFixtures.candidate(segs[0].id, ordinal: 0), dup = StoreFixtures.candidate(segs[0].id, ordinal: 0)
    #expect(throws: CandidateRepository.Error.duplicate) {
        try repo.insertAll([a, dup], markingExtracted: segs[0].id, in: sessions)
    }
    #expect(try repo.candidates(for: segs[0].id).isEmpty)
    #expect(try sessions.fetchSegment(segs[0].id)?.status == .pending)
    try repo.insertAll([a], markingExtracted: segs[0].id, in: sessions)
    #expect(try repo.candidates(for: segs[0].id).count == 1)
    #expect(try sessions.fetchSegment(segs[0].id)?.status == .extracted)
}
