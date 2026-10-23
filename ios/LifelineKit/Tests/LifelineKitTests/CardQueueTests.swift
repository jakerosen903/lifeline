import Foundation
import Testing
@testable import LifelineKit

private func memoryCandidate(_ segment: SegmentID, ordinal: Int = 0) throws -> Candidate {
    let out = MemoryOut(ref: "m", title: "T", quote: "q", segmentSpan: WordSpan(startWord: 0, endWord: 0), peopleRefs: [], placeText: nil,
                        anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
    return StoreFixtures.candidate(segment, ordinal: ordinal, kind: .memory, payload: try CandidatePayload.encode(out))
}
private func mentionCandidate(_ segment: SegmentID, ordinal: Int = 1) throws -> Candidate {
    let out = MentionOut(text: "Maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)
    return StoreFixtures.candidate(segment, ordinal: ordinal, kind: .person, payload: try CandidatePayload.encode(out))
}

@Test func cardQueueAppendsInOrderAndRemoves() throws {
    let segment = SegmentID()
    let a = try memoryCandidate(segment, ordinal: 0), b = try mentionCandidate(segment, ordinal: 1)
    var queue = CardQueue()
    queue.apply(.candidates([a, b], segment: segment))
    #expect(queue.cards.map(\.id) == [a.id.rawValue, b.id.rawValue])
    guard case .memory(let c, let out) = queue.cards[0] else { Issue.record("expected memory card"); return }
    #expect(c.id == a.id && out.title == "T")
    guard case .whoIsThis(.candidate(let who), let text) = queue.cards[1] else { Issue.record("expected who-is-this card"); return }
    #expect(who.id == b.id && text == "Maya")
    queue.remove(a.id.rawValue)
    #expect(queue.cards.map(\.id) == [b.id.rawValue])
    queue.apply(.candidates([a], segment: segment))
    queue.apply(.candidates([a], segment: segment))
    #expect(queue.cards.count == 2, "the same candidate is never shown twice")
}

@Test func seriousDisclosureSuppressesLaterMemoryCards() throws {
    let segment = SegmentID()
    var queue = CardQueue()
    queue.apply(.flags(Flags(seriousDisclosure: true, wantsToStop: false, wantsToChangeSubject: false), segment: segment))
    #expect(queue.suppressed)
    queue.apply(.candidates([try memoryCandidate(segment), try mentionCandidate(segment)], segment: segment))
    #expect(queue.cards.count == 1)
    guard case .whoIsThis = queue.cards[0] else { Issue.record("expected a who-is-this card"); return }
}

@Test func otherFlagsDoNotSuppress() throws {
    let segment = SegmentID()
    var queue = CardQueue()
    queue.apply(.flags(Flags(seriousDisclosure: false, wantsToStop: true, wantsToChangeSubject: true), segment: segment))
    queue.apply(.candidates([try memoryCandidate(segment)], segment: segment))
    #expect(!queue.suppressed && queue.cards.count == 1)
}

@Test func undecodablePayloadIsNotACard() {
    let segment = SegmentID()
    var queue = CardQueue()
    queue.apply(.candidates([StoreFixtures.candidate(segment, kind: .memory, payload: "{}")], segment: segment))
    #expect(queue.cards.isEmpty)
}

@Test func waitingCardsHoldHintsUntilTheirMemoryIsAccepted() throws {
    let segment = SegmentID()
    let memory = try memoryCandidate(segment, ordinal: 0)
    let hintOut = HintOut(kind: .collection, phrase: "every summer", memoryCandidateID: memory.id.rawValue)
    let hint = StoreFixtures.candidate(segment, ordinal: 1, kind: .hint, payload: try CandidatePayload.encode(hintOut))
    let orphan = StoreFixtures.candidate(segment, ordinal: 2, kind: .hint, payload: try CandidatePayload.encode(HintOut(kind: .chapter, phrase: "x", memoryCandidateID: "gone")))
    let pendingMemory = CardQueue.waitingCards(pending: [memory, hint, orphan], statusOf: { id in id == memory.id ? .pending : nil })
    #expect(pendingMemory.map(\.id) == [memory.id.rawValue], "a hint waits for its memory; an orphan hint is never shown")
    let accepted = CardQueue.waitingCards(pending: [hint, orphan], statusOf: { id in id == memory.id ? .accepted : nil })
    #expect(accepted.map(\.id) == [hint.id.rawValue])
    let dismissed = CardQueue.waitingCards(pending: [hint], statusOf: { _ in .dismissed })
    #expect(dismissed.isEmpty)
}
