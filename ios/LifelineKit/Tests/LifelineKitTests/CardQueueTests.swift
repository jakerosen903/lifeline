import Foundation
import Testing
@testable import LifelineKit

private func memoryCandidate(_ segment: SegmentID, ordinal: Int = 0) throws -> Candidate {
    let out = MemoryOut(ref: "m", title: "T", quote: "q", segmentSpan: WordSpan(startWord: 0, endWord: 0), peopleRefs: [], placeText: nil,
                        anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
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
    let c2 = try memoryCandidate(segment, ordinal: 2)
    queue.apply(.candidates([a, b, c2], segment: segment))
    #expect(queue.cards.map(\.id) == [a.id.rawValue, c2.id.rawValue], "a who-is-this is a follow-up, never a card")
    guard case .memory(let c, let out) = queue.cards[0] else { Issue.record("expected memory card"); return }
    #expect(c.id == a.id && out.title == "T")
    queue.remove(a.id.rawValue)
    #expect(queue.cards.map(\.id) == [c2.id.rawValue])
    queue.apply(.candidates([a], segment: segment))
    queue.apply(.candidates([a], segment: segment))
    #expect(queue.cards.count == 2, "the same candidate is never shown twice")
}

@Test func disclosureSuppressesOrganizationalPrompts() throws {
    // During a heavy moment no organizational prompt of any kind appears, who-is-this included.
    let segment = SegmentID()
    var queue = CardQueue()
    queue.apply(.flags(Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false), segment: segment))
    #expect(queue.suppressed)
    queue.apply(.candidates([try memoryCandidate(segment), try mentionCandidate(segment)], segment: segment))
    #expect(queue.cards.isEmpty)
}

@Test func wantsToStopSuppressesTooButChangeSubjectDoesNot() throws {
    let segment = SegmentID()
    var stopping = CardQueue()
    stopping.apply(.flags(Flags(disclosure: .none, wantsToStop: true, wantsToChangeSubject: false), segment: segment))
    stopping.apply(.candidates([try memoryCandidate(segment)], segment: segment))
    #expect(stopping.suppressed && stopping.cards.isEmpty)
    var changing = CardQueue()
    changing.apply(.flags(Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: true), segment: segment))
    changing.apply(.candidates([try memoryCandidate(segment)], segment: segment))
    #expect(!changing.suppressed && changing.cards.count == 1)
}

@Test func undecodablePayloadIsNotACard() {
    let segment = SegmentID()
    var queue = CardQueue()
    queue.apply(.candidates([StoreFixtures.candidate(segment, kind: .memory, payload: "{}")], segment: segment))
    #expect(queue.cards.isEmpty)
}

@Test func possibleMemoryCountCountsMemoryCardsOnly() throws {
    let segment = SegmentID()
    var queue = CardQueue()
    #expect(queue.possibleMemoryCount == 0)
    queue.apply(.candidates([try memoryCandidate(segment), try mentionCandidate(segment)], segment: segment))
    #expect(queue.possibleMemoryCount == 1, "a who-is-this card is not a memory")
    queue.apply(.candidates([try memoryCandidate(segment, ordinal: 2)], segment: segment))
    #expect(queue.possibleMemoryCount == 2)
    let first = queue.cards[0].id
    queue.remove(first)
    queue.memoryAccepted(first)
    #expect(queue.possibleMemoryCount == 1, "a kept memory is no longer only possible")
}

@Test func cardQueueReplacesACardWithTheSameID() throws {
    let segment = SegmentID()
    let a = try memoryCandidate(segment, ordinal: 0), b = try mentionCandidate(segment, ordinal: 1)
    var queue = CardQueue()
    queue.apply(.candidates([a, b], segment: segment))
    var out = try #require(CandidatePayload.memory(a))
    out.extraSpans = [ExtraSpan(segmentID: SegmentID().rawValue, startWord: 0, endWord: 2)]
    var changed = a
    changed.payload = try CandidatePayload.encode(out)
    queue.apply(.candidates([changed], segment: segment))
    #expect(queue.cards.map(\.id) == [a.id.rawValue], "same position, still one card")
    guard case .memory(_, let shown) = queue.cards[0] else { Issue.record("expected memory card"); return }
    #expect(shown.extraSpans.count == 1)
}

// MARK: - Follow-ups under their memory

private func memory(_ s: SegmentID, _ ordinal: Int, title: String = "T", people: [String] = [], things: [String] = [],
                    status: CandidateStatus = .pending) throws -> Candidate {
    let out = MemoryOut(ref: "m\(ordinal)", title: title, quote: "q", segmentSpan: WordSpan(startWord: 0, endWord: 0), peopleRefs: people, placeText: nil,
                        anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9,
                        entityRefs: things.map { EntityRefOut(text: $0, kind: .thing, likelyEntityID: nil) })
    var c = StoreFixtures.candidate(s, ordinal: ordinal, kind: .memory, payload: try CandidatePayload.encode(out))
    c.status = status
    return c
}
private func hint(_ s: SegmentID, _ ordinal: Int, for memory: Candidate, phrase: String = "family") throws -> Candidate {
    StoreFixtures.candidate(s, ordinal: ordinal, kind: .hint,
                            payload: try CandidatePayload.encode(HintOut(kind: .domain, phrase: phrase, memoryCandidateID: memory.id.rawValue)))
}
private func person(_ s: SegmentID, _ ordinal: Int, _ text: String) throws -> Candidate {
    StoreFixtures.candidate(s, ordinal: ordinal, kind: .person,
                            payload: try CandidatePayload.encode(MentionOut(text: text, kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)))
}
private func thing(_ s: SegmentID, _ ordinal: Int, _ text: String) throws -> Candidate {
    StoreFixtures.candidate(s, ordinal: ordinal, kind: .entity,
                            payload: try CandidatePayload.encode(MentionOut(text: text, kind: .thing, likelyAliasOfPersonID: nil, confidence: 0.8)))
}
private func kept(_ queue: CardQueue, _ memory: Candidate) -> KeptCard? {
    for case .kept(let k) in queue.cards where k.memoryCandidateID == memory.id.rawValue { return k }
    return nil
}
private func ids(_ candidates: Candidate...) -> [String] { candidates.map(\.id.rawValue) }

@Test func followUpsNeverBecomeCards() throws {
    let s = SegmentID()
    let a = try memory(s, 0, people: ["Maya"], things: ["the shed"])
    var queue = CardQueue()
    queue.apply(.candidates([a, try hint(s, 1, for: a), try person(s, 2, "Maya"), try thing(s, 3, "the shed"), try person(s, 4, "Zed")], segment: s))
    #expect(queue.cards.map(\.id) == ids(a), "follow-ups wait under their memory; one with no owner never shows")
}

@Test func keepWithFollowUpsLeavesAKeptCardInPlace() throws {
    let s = SegmentID()
    let a = try memory(s, 0), b = try memory(s, 1, title: "The steak dinner"), c = try memory(s, 2)
    let h = try hint(s, 3, for: b)
    var queue = CardQueue()
    queue.apply(.candidates([a, b, c, h], segment: s))
    queue.memoryAccepted(b.id.rawValue)
    #expect(queue.cards.map(\.id) == ids(a, b, c), "same place, same id")
    let k = try #require(kept(queue, b))
    #expect(k.title == "The steak dinner" && k.followUps.map(\.id) == ids(h) && k.answered.isEmpty && !k.isComplete)
    #expect(queue.possibleMemoryCount == 2, "a kept card is no longer a possible memory")
}

@Test func keepWithoutFollowUpsRemovesTheCard() throws {
    let s = SegmentID()
    let a = try memory(s, 0), b = try memory(s, 1)
    var queue = CardQueue()
    queue.apply(.candidates([a, b, try hint(s, 2, for: b)], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    #expect(queue.cards.map(\.id) == ids(b))
}

@Test func dismissHidesFollowUpsAndUndoRestoresThem() throws {
    let s = SegmentID()
    let a = try memory(s, 0, people: ["Theo"])
    let h = try hint(s, 1, for: a), p = try person(s, 2, "Theo")
    var queue = CardQueue()
    queue.apply(.candidates([a, h, p], segment: s))
    let card = queue.cards[0]
    queue.memoryDismissed(a.id.rawValue)
    #expect(queue.cards.isEmpty, "dismiss takes the card and hides its follow-ups with it")
    queue.restore(card)
    #expect(queue.cards == [card])
    queue.memoryAccepted(a.id.rawValue)
    #expect(kept(queue, a)?.followUps.map(\.id) == ids(h, p), "undo brought the follow-ups back, in emitted order")
}

@Test func dismissPassesEntityToNextMemory() throws {
    let s = SegmentID()
    let a = try memory(s, 0, people: ["Theo"]), b = try memory(s, 1, people: ["Theo"])
    let p = try person(s, 2, "Theo")
    var queue = CardQueue()
    queue.apply(.candidates([a, b, p], segment: s))
    queue.memoryDismissed(a.id.rawValue)
    queue.memoryAccepted(b.id.rawValue)
    #expect(kept(queue, b)?.followUps.map(\.id) == ids(p))
}

@Test func answeredReportsCompletion() throws {
    let s = SegmentID()
    let a = try memory(s, 0, people: ["Theo"])
    let h = try hint(s, 1, for: a), p = try person(s, 2, "Theo")
    var queue = CardQueue()
    queue.apply(.candidates([a, h, p], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    let first = queue.answered(h.id.rawValue, in: a.id.rawValue)
    #expect(!first && kept(queue, a)?.answered == [h.id.rawValue])
    let second = queue.answered(p.id.rawValue, in: a.id.rawValue)
    #expect(second && kept(queue, a)?.isComplete == true, "the card stays until the app closes it")
    let unknown = queue.answered("nope", in: "nothing")
    #expect(!unknown)
}

@Test func closeKeptSortsDismissAndMention() throws {
    let s = SegmentID()
    let a = try memory(s, 0, people: ["Theo"], things: ["the shed"])
    let h = try hint(s, 1, for: a), h2 = try hint(s, 2, for: a, phrase: "work"), t = try thing(s, 3, "the shed"), p = try person(s, 4, "Theo")
    var queue = CardQueue()
    queue.apply(.candidates([a, h, h2, t, p], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    _ = queue.answered(h.id.rawValue, in: a.id.rawValue)
    let close = queue.closeKept(a.id.rawValue)
    #expect(close.dismiss.map(\.id) == ids(h2, t) && close.openAsMention.map(\.id) == ids(p))
    #expect(queue.cards.isEmpty)
    let again = queue.closeKept(a.id.rawValue)
    #expect(again == KeptClose(dismiss: [], openAsMention: []), "closed once")
}

@Test func closeKeptOfACompleteCardIsEmpty() throws {
    let s = SegmentID()
    let a = try memory(s, 0)
    let h = try hint(s, 1, for: a)
    var queue = CardQueue()
    queue.apply(.candidates([a, h], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    let complete = queue.answered(h.id.rawValue, in: a.id.rawValue)
    #expect(complete)
    let close = queue.closeKept(a.id.rawValue)
    #expect(close == KeptClose(dismiss: [], openAsMention: []))
    #expect(queue.cards.isEmpty)
}

@Test func closeAllKeptClosesEveryOpenCard() throws {
    // Review focus 4: Keep on B while A's kept card is open closes A first, exactly once.
    let s = SegmentID()
    let a = try memory(s, 0, people: ["Theo"]), b = try memory(s, 1)
    let p = try person(s, 2, "Theo"), hb = try hint(s, 3, for: b)
    var queue = CardQueue()
    queue.apply(.candidates([a, b, p, hb], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    let first = queue.closeAllKept()
    queue.memoryAccepted(b.id.rawValue)
    #expect(first.dismiss.isEmpty && first.openAsMention.map(\.id) == ids(p))
    #expect(queue.cards.map(\.id) == ids(b) && kept(queue, b) != nil)
    let late = try hint(SegmentID(), 0, for: a)
    queue.apply(.candidates([late], segment: late.segmentID))
    #expect(queue.cards.map(\.id) == ids(b, a), "a late follow-up for A opens a kept card of its own")
    let second = queue.closeAllKept()
    #expect(second.dismiss.map(\.id) == ids(hb, late) && second.openAsMention.isEmpty, "A's person was reported once, not again")
    #expect(queue.cards.isEmpty)
}

@Test func lateFollowUpJoinsOpenKeptCard() throws {
    // Review focus 1.
    let s = SegmentID(), later = SegmentID()
    let a = try memory(s, 0)
    let h1 = try hint(s, 1, for: a), h2 = try hint(later, 0, for: a, phrase: "work")
    var queue = CardQueue()
    queue.apply(.candidates([a, h1], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    queue.apply(.candidates([h2], segment: later))
    #expect(queue.cards.map(\.id) == ids(a))
    #expect(kept(queue, a)?.followUps.map(\.id) == ids(h1, h2))
}

@Test func lateFollowUpAfterCloseMakesNewKeptCard() throws {
    let s = SegmentID(), later = SegmentID()
    let a = try memory(s, 0, title: "The shed"), b = try memory(s, 1)
    let h1 = try hint(s, 2, for: b)
    var queue = CardQueue()
    queue.apply(.candidates([a, b, h1], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    #expect(queue.cards.map(\.id) == ids(b), "no follow-ups yet: the card left")
    queue.memoryAccepted(b.id.rawValue)
    _ = queue.closeKept(b.id.rawValue)
    let ha = try hint(later, 0, for: a), hb = try hint(later, 1, for: b)
    queue.apply(.candidates([ha, hb], segment: later))
    #expect(queue.cards.map(\.id) == ids(a, b))
    #expect(kept(queue, a)?.title == "The shed" && kept(queue, a)?.followUps.map(\.id) == ids(ha))
    #expect(kept(queue, b)?.followUps.map(\.id) == ids(hb))
}

@Test func suppressedKeepShowsNoChips() throws {
    // Review focus 3.
    let s = SegmentID()
    let a = try memory(s, 0)
    var queue = CardQueue()
    queue.apply(.candidates([a, try hint(s, 1, for: a)], segment: s))
    queue.apply(.flags(Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false), segment: s))
    queue.memoryAccepted(a.id.rawValue)
    #expect(queue.cards.isEmpty, "the card leaves as if it had no follow-ups")
    queue.apply(.candidates([try hint(SegmentID(), 0, for: a)], segment: s))
    #expect(queue.cards.isEmpty)
}

@Test func continuationKeepsHeldFollowUps() throws {
    let s = SegmentID()
    let a = try memory(s, 0, title: "Old")
    let h = try hint(s, 1, for: a)
    var queue = CardQueue()
    queue.apply(.candidates([a, h], segment: s))
    var out = try #require(CandidatePayload.memory(a))
    out.title = "New"
    var changed = a
    changed.payload = try CandidatePayload.encode(out)
    queue.apply(.candidates([changed], segment: SegmentID()))
    queue.memoryAccepted(a.id.rawValue)
    #expect(kept(queue, a)?.title == "New" && kept(queue, a)?.followUps.map(\.id) == ids(h))
}

@Test func restoreTakesFollowUpsBackFromKeptCard() throws {
    // Undo of "Same story": the kept card turns back into the memory card, its follow-ups held again.
    let s = SegmentID()
    let a = try memory(s, 0)
    let h = try hint(s, 1, for: a)
    var queue = CardQueue()
    queue.apply(.candidates([a, h], segment: s))
    let card = queue.cards[0]
    queue.memoryAccepted(a.id.rawValue)
    queue.restore(card)
    #expect(queue.cards == [card])
    queue.memoryAccepted(a.id.rawValue)
    #expect(kept(queue, a)?.followUps.map(\.id) == ids(h))
}

@Test func waitingGroupsFollowUpsUnderAcceptedMemory() throws {
    // Review focus 5: the app was closed after Keep; the follow-ups wait as one kept card.
    let s = SegmentID()
    let pendingMemory = try memory(s, 0), keptMemory = try memory(s, 1, title: "Kept one", people: ["Theo"], status: .accepted)
    let hp = try hint(s, 2, for: pendingMemory), hk = try hint(s, 3, for: keptMemory), p = try person(s, 4, "Theo"), orphan = try person(s, 5, "Zed")
    let byID = Dictionary(uniqueKeysWithValues: [pendingMemory, keptMemory].map { ($0.id, $0) })
    var queue = CardQueue.waiting(pending: [pendingMemory, hp, hk, p, orphan], segmentMemories: { $0 == s ? [pendingMemory, keptMemory] : [] },
                                  candidate: { byID[$0] })
    #expect(queue.cards.map(\.id) == ids(pendingMemory, keptMemory))
    guard case .memory = queue.cards[0] else { Issue.record("expected a memory card"); return }
    #expect(kept(queue, keptMemory)?.title == "Kept one" && kept(queue, keptMemory)?.followUps.map(\.id) == ids(hk, p))
    queue.memoryAccepted(pendingMemory.id.rawValue)
    #expect(kept(queue, pendingMemory)?.followUps.map(\.id) == ids(hp), "a pending memory held its follow-ups")
}

@Test func waitingDropsFollowUpsOfDismissedMemory() throws {
    let s = SegmentID()
    let gone = try memory(s, 0, people: ["Theo", "Zed"], status: .dismissed), kept1 = try memory(s, 1, people: ["Theo"], status: .accepted)
    let h = try hint(s, 2, for: gone), theo = try person(s, 3, "Theo"), zed = try person(s, 4, "Zed")
    let missing = StoreFixtures.candidate(s, ordinal: 5, kind: .hint, payload: try CandidatePayload.encode(HintOut(kind: .chapter, phrase: "x", memoryCandidateID: "gone")))
    let byID = Dictionary(uniqueKeysWithValues: [gone, kept1].map { ($0.id, $0) })
    let queue = CardQueue.waiting(pending: [h, theo, zed, missing], segmentMemories: { _ in [gone, kept1] }, candidate: { byID[$0] })
    #expect(queue.cards.map(\.id) == ids(kept1), "Theo passes to the next memory; Zed and the hints have none")
    #expect(kept(queue, kept1)?.followUps.map(\.id) == ids(theo))
}

@Test func waitingTitlesAKeptCardWhoseSegmentHasNothingPending() throws {
    // A continuation's hint sits in a later segment than its accepted memory.
    let first = SegmentID(), later = SegmentID()
    let a = try memory(first, 0, title: "The pomegranate tree", status: .accepted)
    let h = try hint(later, 0, for: a)
    let queue = CardQueue.waiting(pending: [h], segmentMemories: { $0 == first ? [a] : [] }, candidate: { $0 == a.id ? a : nil })
    #expect(kept(queue, a)?.title == "The pomegranate tree" && kept(queue, a)?.followUps.map(\.id) == ids(h))
    let unknown = CardQueue.waiting(pending: [h], segmentMemories: { _ in [] }, candidate: { _ in nil })
    #expect(unknown.cards.isEmpty, "an owner the queue cannot see never gets a blank kept card")
}

@Test func continuationOfAKeptMemoryIsNotReappended() throws {
    let s = SegmentID()
    let a = try memory(s, 0, title: "Old"), b = try memory(s, 1, title: "Old")
    var queue = CardQueue()
    queue.apply(.candidates([a, b, try hint(s, 2, for: b)], segment: s))
    queue.memoryAccepted(a.id.rawValue)
    queue.memoryAccepted(b.id.rawValue)
    #expect(queue.cards.map(\.id) == ids(b))
    for c in [a, b] {
        var out = try #require(CandidatePayload.memory(c))
        out.title = "New"
        var changed = c
        changed.payload = try CandidatePayload.encode(out)
        queue.apply(.candidates([changed], segment: SegmentID()))
    }
    #expect(queue.cards.map(\.id) == ids(b), "A left on Keep and stays gone")
    #expect(kept(queue, b)?.title == "New", "the open kept card takes the new title")
}

@Test func continuationOfADismissedMemoryIsNotReappended() throws {
    let s = SegmentID()
    let a = try memory(s, 0)
    var queue = CardQueue()
    queue.apply(.candidates([a], segment: s))
    queue.memoryDismissed(a.id.rawValue)
    queue.apply(.candidates([a], segment: SegmentID()))
    #expect(queue.cards.isEmpty)
}

@Test func keepOpenCarriesAnsweredChipsAcrossARebuild() throws {
    // Session detail and the timeline rebuild from the store; a kept card being answered stays put.
    let s = SegmentID()
    let a = try memory(s, 0, title: "The shed", status: .accepted), b = try memory(s, 1), c = try memory(s, 2, title: "All done", status: .accepted)
    let h1 = try hint(s, 3, for: a), h2 = try hint(s, 4, for: a, phrase: "work"), hc = try hint(s, 5, for: c), late = try hint(s, 6, for: a, phrase: "home")
    let byID = Dictionary(uniqueKeysWithValues: [a, b, c].map { ($0.id, $0) })
    var old = CardQueue.waiting(pending: [b, h1, h2, hc], segmentMemories: { _ in [a, b, c] }, candidate: { byID[$0] })
    #expect(old.cards.map(\.id) == ids(b, a, c))
    _ = old.answered(h1.id.rawValue, in: a.id.rawValue)
    _ = old.answered(hc.id.rawValue, in: c.id.rawValue)
    // The store now: h1 and hc answered, a late follow-up for a.
    var fresh = CardQueue.waiting(pending: [b, h2, late], segmentMemories: { _ in [a, b, c] }, candidate: { byID[$0] })
    fresh.keepOpen(from: old)
    #expect(fresh.cards.map(\.id) == ids(b, a, c), "same places; the complete card is not dropped")
    #expect(kept(fresh, a)?.followUps.map(\.id) == ids(h1, h2, late) && kept(fresh, a)?.answered == [h1.id.rawValue])
    #expect(kept(fresh, c)?.isComplete == true)
    #expect(fresh.closeKept(c.id.rawValue) == KeptClose(), "a complete card closes with nothing left")
}

@Test func keepOpenHoldsTheCardsPlaceWhenTheStoreOrdersItLater() throws {
    // Kept on screen in place of its memory; rebuilt, its follow-up comes after the next memory.
    let s = SegmentID()
    let a = try memory(s, 0, title: "First"), b = try memory(s, 1)
    let h = try hint(s, 2, for: a)
    let accepted = { var m = a; m.status = .accepted; return m }()
    var old = CardQueue.waiting(pending: [a, b, h], segmentMemories: { _ in [a, b] }, candidate: { $0 == a.id ? a : $0 == b.id ? b : nil })
    old.memoryAccepted(a.id.rawValue)
    #expect(old.cards.map(\.id) == ids(a, b))
    var fresh = CardQueue.waiting(pending: [b, h], segmentMemories: { _ in [accepted, b] }, candidate: { $0 == a.id ? accepted : $0 == b.id ? b : nil })
    fresh.keepOpen(from: old)
    #expect(fresh.cards.map(\.id) == ids(a, b), "the kept card stays first")
    fresh.memoryAccepted(b.id.rawValue)
    #expect(fresh.cards.map(\.id) == ids(a), "the rebuilt queue still settles memories")
}
