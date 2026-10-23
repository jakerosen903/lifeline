import Foundation
import Testing
@testable import LifelineKit

private struct Env {
    let store: ExtractionStore, actions: CandidateActions, session: SessionID, segment: Segment
    init() throws {
        let db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = CandidateActions(store: store)
        (session, _) = try StoreFixtures.session(in: store.sessions, segments: ["we went up to Yosemite every August in the station wagon"])
        segment = try store.sessions.segments(in: session)[0]
    }
    func memoryCandidate(ordinal: Int = 0, collection: String? = nil, chapter: String? = nil) throws -> Candidate {
        let out = MemoryOut(ref: "m1", kind: .event, title: "The station wagon", quote: "the station wagon", segmentSpan: WordSpan(startWord: 7, endWord: 8),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: collection, chapterHint: chapter, confidence: 0.9)
        let c = StoreFixtures.candidate(segment.id, ordinal: ordinal, kind: .memory, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return c
    }
    func hintCandidate(for memory: Candidate, kind: HintKind, phrase: String, ordinal: Int) throws -> Candidate {
        let out = HintOut(kind: kind, phrase: phrase, memoryCandidateID: memory.id.rawValue)
        let c = StoreFixtures.candidate(segment.id, ordinal: ordinal, kind: .hint, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return c
    }
}

@Test func hintCardWaitsForItsMemory() throws {
    let env = try Env()
    let memory = try env.memoryCandidate(collection: "every August")
    let hint = try env.hintCandidate(for: memory, kind: .collection, phrase: "every August", ordinal: 1)
    var queue = CardQueue()
    queue.apply(.candidates([memory, hint], segment: env.segment.id))
    #expect(queue.cards.map(\.id) == [memory.id.rawValue], "the hint waits until the memory is accepted")
    queue.remove(memory.id.rawValue)
    queue.memoryAccepted(memory.id.rawValue)
    guard case .hint(let c, let out)? = queue.cards.first else { Issue.record("expected a hint card, got \(queue.cards)"); return }
    #expect(c.id == hint.id && out.phrase == "every August" && out.kind == .collection)
    queue.remove(memory.id.rawValue)   // dismissing the memory instead drops its hint
    var other = CardQueue()
    other.apply(.candidates([memory, hint], segment: env.segment.id))
    other.remove(memory.id.rawValue)
    other.memoryDismissed(memory.id.rawValue)
    #expect(other.cards.isEmpty && other.heldHintCount == 0)
}

@Test func acceptingACollectionHintCreatesAndFillsTheCollection() throws {
    let env = try Env()
    let memoryCandidate = try env.memoryCandidate(collection: "every August")
    let accepted = try env.actions.acceptMemory(memoryCandidate)
    let hint = try env.hintCandidate(for: memoryCandidate, kind: .collection, phrase: "every August", ordinal: 1)
    let result = try env.actions.acceptHint(hint)
    guard case .collection(let collection) = result else { Issue.record("expected a collection"); return }
    #expect(collection.title == "every August")
    #expect(try env.store.chapters.members(of: collection.id).map(\.id) == [accepted.memory.id])
    #expect(try env.store.candidates.fetch(hint.id)?.status == .accepted)
    #expect(throws: CandidateActions.Error.notPending) { try env.actions.acceptHint(hint) }
}

@Test func acceptingAChapterHintReusesAnExistingTitle() throws {
    let env = try Env()
    let existing = try env.store.chapters.insertChapter(title: "Childhood")
    let memoryCandidate = try env.memoryCandidate(chapter: "childhood")
    let accepted = try env.actions.acceptMemory(memoryCandidate)
    let hint = try env.hintCandidate(for: memoryCandidate, kind: .chapter, phrase: "childhood", ordinal: 1)
    guard case .chapter(let chapter) = try env.actions.acceptHint(hint) else { Issue.record("expected a chapter"); return }
    #expect(chapter.id == existing.id)
    #expect(try env.store.chapters.chapters().count == 1)
    #expect(try env.store.memories.fetch(accepted.memory.id)?.chapterID == existing.id)
}

@Test func hintBeforeItsMemoryIsAcceptedIsRejected() throws {
    let env = try Env()
    let memoryCandidate = try env.memoryCandidate(collection: "every August")
    let hint = try env.hintCandidate(for: memoryCandidate, kind: .collection, phrase: "every August", ordinal: 1)
    #expect(throws: CandidateActions.Error.memoryNotAccepted) { try env.actions.acceptHint(hint) }
}

@Test func chapterRangeFollowsItsMembers() throws {
    let env = try Env()
    let a = try env.actions.acceptMemory(try env.memoryCandidate(ordinal: 0)).memory
    let b = try env.actions.acceptMemory(try env.memoryCandidate(ordinal: 1)).memory
    try env.store.memories.updateRange(a.id, .year(1998, origin: .stated, evidence: nil))
    try env.store.memories.updateRange(b.id, .year(2004, origin: .stated, evidence: nil))
    let chapter = try env.actions.createChapter(title: "Growing up", containing: a.id)
    #expect(try env.store.chapters.chapter(id: chapter.id)?.range.earliest?.year == 1998)
    try env.actions.assign(memory: b.id, toChapter: chapter.id)
    let range = try #require(try env.store.chapters.chapter(id: chapter.id)?.range)
    #expect(range.earliest?.year == 1998 && range.latest?.year == 2004 && range.origin == .derived)
    let trips = try env.actions.addToCollection(a.id, titled: "Family trips")
    #expect(try env.store.chapters.members(of: trips.id).count == 1)
    try env.actions.removeFromCollection(a.id, from: trips.id)
    #expect(try env.store.chapters.members(of: trips.id).isEmpty)
}

@Test func queueStoresAHintRowAfterItsMemory() async throws {
    let env = try Env()
    var out = ExtractorOutput(memories: [], mentions: [], flags: .none)
    out.memories = [MemoryOut(ref: "m1", kind: .event, title: "The station wagon", quote: "the station wagon", segmentSpan: WordSpan(startWord: 7, endWord: 8),
                              peopleRefs: [], placeText: nil, anchors: [], collectionHint: "every August", chapterHint: nil, confidence: 0.9)]
    let service = FakeExtractionService([.success(out)])
    let queue = ExtractionQueue(session: env.session, service: service, store: env.store)
    await queue.enqueue(env.segment.id)
    await queue.drain()
    let rows = try env.store.candidates.candidates(for: env.segment.id)
    #expect(rows.map(\.kind) == [.memory, .hint])
    let hint = try #require(CandidatePayload.hint(rows[1]))
    #expect(hint.memoryCandidateID == rows[0].id.rawValue && hint.phrase == "every August" && hint.kind == .collection)
}
