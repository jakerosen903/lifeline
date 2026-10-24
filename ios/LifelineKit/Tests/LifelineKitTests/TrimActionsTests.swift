import Foundation
import Testing
@testable import LifelineKit

/// "Which part of the recording": the span moves to the person's words; the card follows (M6).
private struct Env {
    let store: ExtractionStore, actions: CandidateActions
    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
    }

    /// A ten-word segment whose card covers words 1…3.
    func kept(extra: String? = nil) throws -> (Memory, Candidate, [Segment]) {
        let texts = ["one two three four five six seven eight nine ten"] + (extra.map { [$0] } ?? [])
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: texts)
        let out = MemoryOut(ref: "m1", kind: .event, title: "Three words", quote: "two three four", segmentSpan: WordSpan(startWord: 1, endWord: 3), peopleRefs: [], placeText: nil,
                            anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9,
                            extraSpans: extra == nil ? [] : [ExtraSpan(segmentID: segs[1].id.rawValue, startWord: 0, endWord: 2)])
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return (try actions.acceptMemory(c).memory, c, segs)
    }
}

@Test func trimMovesTheSpanToWordBoundariesAndRewritesTheCard() throws {
    let env = try Env()
    let (memory, card, segs) = try env.kept()
    let words = try env.store.sessions.words(in: segs[0].id)
    let receipt = try env.actions.trimTelling(memory.id, order: 0, startWord: 0, endWord: 5)
    let span = try #require(try env.store.memories.spans(of: memory.id).first)
    #expect(span.startMs == words[0].startMs && span.endMs == words[5].endMs && span.segmentID == segs[0].id)
    let rewritten = try #require(try env.store.candidates.fetch(card.id))
    #expect(CandidatePayload.memory(rewritten)?.segmentSpan == WordSpan(startWord: 0, endWord: 5))
    #expect(receipt.before.startMs == words[1].startMs && receipt.after == span && receipt.candidateID == card.id)
    try env.actions.undoTrim(receipt)
    let back = try #require(try env.store.memories.spans(of: memory.id).first)
    #expect(back.startMs == words[1].startMs && back.endMs == words[3].endMs)
    let restored = try #require(try env.store.candidates.fetch(card.id))
    #expect(CandidatePayload.memory(restored)?.segmentSpan == WordSpan(startWord: 1, endWord: 3))
}

@Test func trimOfAContinuationPartRewritesExtraSpans() throws {
    let env = try Env()
    let (memory, card, segs) = try env.kept(extra: "alpha beta gamma delta")
    let words = try env.store.sessions.words(in: segs[1].id)
    #expect(try env.store.memories.spans(of: memory.id).count == 2)
    _ = try env.actions.trimTelling(memory.id, order: 1, startWord: 1, endWord: 2)
    let spans = try env.store.memories.spans(of: memory.id)
    #expect(spans[1].startMs == words[1].startMs && spans[1].endMs == words[2].endMs && spans[1].continuesOrder == 0)
    let row = try #require(try env.store.candidates.fetch(card.id))
    let out = try #require(CandidatePayload.memory(row))
    #expect(out.extraSpans == [ExtraSpan(segmentID: segs[1].id.rawValue, startWord: 1, endWord: 2)] && out.segmentSpan == WordSpan(startWord: 1, endWord: 3))
}

@Test func trimOfTheSecondPartInOneSegmentRewritesThatPartOnly() throws {
    let env = try Env()
    let (_, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["one two three four five six seven eight nine ten", "alpha beta gamma delta epsilon zeta eta theta"])
    // A telling carried on twice within the second segment: two parts there, words 0…1 and 4…6.
    let parts = [ExtraSpan(segmentID: segs[1].id.rawValue, startWord: 0, endWord: 1), ExtraSpan(segmentID: segs[1].id.rawValue, startWord: 4, endWord: 6)]
    let out = MemoryOut(ref: "m1", kind: .event, title: "Three words", quote: "two three four", segmentSpan: WordSpan(startWord: 1, endWord: 3), peopleRefs: [], placeText: nil,
                        anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, extraSpans: parts)
    let card = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
    try env.store.candidates.insert(card)
    let memory = try env.actions.acceptMemory(card).memory
    #expect(try env.store.memories.spans(of: memory.id).count == 3)
    _ = try env.actions.trimTelling(memory.id, order: 2, startWord: 5, endWord: 6)
    let row = try #require(try env.store.candidates.fetch(card.id))
    let rewritten = try #require(CandidatePayload.memory(row))
    #expect(rewritten.extraSpans == [parts[0], ExtraSpan(segmentID: segs[1].id.rawValue, startWord: 5, endWord: 6)], "the second part moved; the first did not")
}

@Test func trimIsRefusedWhenTheCardHasNoEntryForThePart() throws {
    let env = try Env()
    let (memory, card, segs) = try env.kept(extra: "alpha beta gamma delta")
    // The card lost its entry for the part (an older payload): moving only the span would split them.
    let row = try #require(try env.store.candidates.fetch(card.id))
    var out = try #require(CandidatePayload.memory(row))
    out.extraSpans = []
    try env.store.candidates.updatePayload(card.id, try CandidatePayload.encode(out))
    let before = try env.store.memories.spans(of: memory.id)
    #expect(throws: CandidateActions.Error.stale) { try env.actions.trimTelling(memory.id, order: 1, startWord: 1, endWord: 2) }
    #expect(try env.store.memories.spans(of: memory.id) == before, "the span did not move either")
    _ = segs
}

@Test func retimeRefusesEmptyAndOutOfSegment() throws {
    let env = try Env()
    let (memory, _, _) = try env.kept()
    let before = try env.store.memories.spans(of: memory.id)
    #expect(throws: CandidateActions.Error.emptySpan) { try env.actions.trimTelling(memory.id, order: 0, startWord: 3, endWord: 2) }
    #expect(throws: CandidateActions.Error.emptySpan) { try env.actions.trimTelling(memory.id, order: 0, startWord: 0, endWord: 40) }
    #expect(throws: CandidateActions.Error.targetMissing) { try env.actions.trimTelling(memory.id, order: 7, startWord: 0, endWord: 1) }
    #expect(try env.store.memories.spans(of: memory.id) == before)
}

@Test func trimUndoIsRefusedAfterALaterEdit() throws {
    let env = try Env()
    let (memory, _, _) = try env.kept()
    let first = try env.actions.trimTelling(memory.id, order: 0, startWord: 0, endWord: 5)
    _ = try env.actions.trimTelling(memory.id, order: 0, startWord: 2, endWord: 4)
    #expect(throws: CandidateActions.Error.stale) { try env.actions.undoTrim(first) }
}

@Test func trimWritesTheCardAndTheSpanTogether() throws {
    let env = try Env()
    let (memory, card, _) = try env.kept()
    let before = try env.store.memories.spans(of: memory.id)
    let payloadBefore = try #require(try env.store.candidates.fetch(card.id)).payload
    // The span is gone (another device's restore, a delete racing the sheet): nothing may change.
    try env.store.memories.deleteSpans(of: memory.id)
    #expect(throws: (any Error).self) {
        try env.store.memories.retime(memory.id, order: 0, startMs: 0, endMs: 10, rewritingCard: (card.id, "{\"changed\":true}"))
    }
    #expect(try env.store.candidates.fetch(card.id)?.payload == payloadBefore, "the card kept its words")
    // Undo checks the card as well as the span.
    for span in before { try env.store.memories.insertSpan(span) }
    let receipt = try env.actions.trimTelling(memory.id, order: 0, startWord: 0, endWord: 5)
    try env.store.candidates.updatePayload(card.id, payloadBefore)   // someone else changed the card meanwhile
    #expect(throws: CandidateActions.Error.stale) { try env.actions.undoTrim(receipt) }
}
