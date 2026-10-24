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

private func memoryPayload(_ text: String, continues: CandidateID? = nil) throws -> String {
    let words = text.split(separator: " ").count
    return try CandidatePayload.encode(MemoryOut(ref: "m1", kind: .event, title: text, quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                                                 peopleRefs: [], placeText: nil, anchors: [], continuesCandidateID: continues?.rawValue,
                                                 collectionHint: nil, chapterHint: nil, confidence: 0.9))
}

@Test func insertAllGrowsTheContinuedCardInTheSameTransaction() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db); let repo = CandidateRepository(db)
    let (_, segs) = try StoreFixtures.session(in: sessions, segments: ["the garden had a tree", "Maya climbed it"])
    let earlier = StoreFixtures.candidate(segs[0].id, payload: try memoryPayload("the garden had a tree"))
    try repo.insert(earlier)
    var row = StoreFixtures.candidate(segs[1].id, payload: try memoryPayload("Maya climbed it", continues: earlier.id))
    row.status = .superseded
    row.rejection = CandidateRepository.continuesReason(earlier.id)
    let span = ExtraSpan(segmentID: segs[1].id.rawValue, startWord: 0, endWord: 2)
    let continuation = CandidateRepository.Continuation(earlierID: earlier.id, rowID: row.id, span: span)
    // A duplicate row fails the insert: the segment stays pending and the earlier card is not grown.
    try repo.insert(StoreFixtures.candidate(segs[1].id, ordinal: 0, payload: "taken"))
    #expect(throws: CandidateRepository.Error.duplicate) { try repo.insertAll([row], markingExtracted: segs[1].id, in: sessions, extending: [continuation]) }
    #expect(try sessions.fetchSegment(segs[1].id)?.status == .pending)
    #expect(CandidatePayload.memory(try #require(try repo.fetch(earlier.id)))?.extraSpans.isEmpty == true)
    // The same write with a free ordinal lands the row, the status and the span together.
    row.ordinal = 1
    let grown = try repo.insertAll([row], markingExtracted: segs[1].id, in: sessions, extending: [continuation])
    #expect(grown == [earlier.id])
    #expect(try sessions.fetchSegment(segs[1].id)?.status == .extracted)
    #expect(CandidatePayload.memory(try #require(try repo.fetch(earlier.id)))?.extraSpans == [span])
    #expect(try repo.fetch(row.id)?.status == .superseded)
}

@Test func insertAllMakesAnOrdinaryCardWhenTheContinuedCardWasKeptFirst() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db); let repo = CandidateRepository(db)
    let memories = MemoryRepository(db)
    let (_, segs) = try StoreFixtures.session(in: sessions, segments: ["the garden had a tree", "Maya climbed it"])
    let earlier = StoreFixtures.candidate(segs[0].id, payload: try memoryPayload("the garden had a tree"))
    try repo.insert(earlier)
    // Keep landed between the queue's check and its write.
    let kept = StoreFixtures.memory(from: earlier.id)
    try memories.insert(kept, spans: [MemorySpan(memoryID: kept.id, segmentID: segs[0].id, startMs: 0, endMs: 100, order: 0)], people: [], places: [], anchors: [],
                        acceptingCandidate: earlier.id)
    var row = StoreFixtures.candidate(segs[1].id, payload: try memoryPayload("Maya climbed it", continues: earlier.id))
    row.status = .superseded
    row.rejection = CandidateRepository.continuesReason(earlier.id)
    let span = ExtraSpan(segmentID: segs[1].id.rawValue, startWord: 0, endWord: 2)
    let grown = try repo.insertAll([row], markingExtracted: segs[1].id, in: sessions,
                                   extending: [.init(earlierID: earlier.id, rowID: row.id, span: span)])
    #expect(grown.isEmpty, "a kept card is not grown")
    let stored = try #require(try repo.fetch(row.id))
    #expect(stored.status == .pending && stored.rejection == nil, "the continuation is an ordinary card")
    let out = try #require(CandidatePayload.memory(stored))
    #expect(out.sameAsMemoryIDs == [kept.id.rawValue] && out.continuesCandidateID == nil, "that names the kept memory")
    #expect(CandidatePayload.memory(try #require(try repo.fetch(earlier.id)))?.extraSpans.isEmpty == true)
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
