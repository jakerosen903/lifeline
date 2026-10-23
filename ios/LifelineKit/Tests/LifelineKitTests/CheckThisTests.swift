import Foundation
import Testing
@testable import LifelineKit

private func mention(_ text: String, status: MentionStatus = .unresolved) -> Mention {
    Mention(id: .init(), segmentID: SegmentID(rawValue: "g"), text: text, status: status, personID: nil, relationText: nil)
}

@Test func checkThisListsInferredRangeAndOpenNames() {
    let range = TimeRange.year(1998, origin: .inferred, evidence: "when I was six")
    let maya = mention("Maya"), again = mention("maya"), known = mention("Andy", status: .resolved)
    let tags = CheckThisTags.tags(range: range, mentions: [maya, again, known])
    #expect(tags == [.range("around 1998"), .person(name: "Maya", mention: maya.id)], "one tag per open name, the range first")
    #expect(tags.map(\.label) == ["Check this: around 1998?", "Check this: Maya?"])
}

@Test func statedAndConfirmedRangesNeedNoCheck() {
    #expect(CheckThisTags.tags(range: .year(1998, origin: .stated, evidence: "in 1998"), mentions: []).isEmpty)
    #expect(CheckThisTags.tags(range: .year(1998, origin: .confirmed, evidence: nil), mentions: []).isEmpty)
    #expect(CheckThisTags.tags(range: .unplaced, mentions: []).isEmpty, "nothing to check until there is a guess")
}

@Test func lowConfidenceIsALabelNeverAFade() {
    #expect(CheckThisTags.tags(range: .unplaced, mentions: [], confidence: 0.3) == [.lowConfidence])
    #expect(CheckThisTags.tags(range: .unplaced, mentions: [], confidence: 0.5).isEmpty)
    #expect(CheckThis.lowConfidence.label == "Check this")
}

@Test func dismissUndoRestoresTheCard() throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let actions = CandidateActions(store: store)
    let (_, segments) = try StoreFixtures.session(in: store.sessions)
    let out = MemoryOut(ref: "m1", kind: .event, title: "The pomegranate tree", quote: "pomegranate tree", segmentSpan: WordSpan(startWord: 4, endWord: 5),
                        peopleRefs: [], placeText: nil, anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
    let candidate = StoreFixtures.candidate(segments[0].id, payload: try CandidatePayload.encode(out))
    try store.candidates.insert(candidate)
    let card = Card.memory(candidate, out)
    let t0 = Date(timeIntervalSince1970: 1_000)

    var undo = DismissUndo<Card>(window: .seconds(6))
    try actions.dismiss(candidate)
    undo.dismissed(card, at: t0)
    #expect(try store.candidates.fetch(candidate.id)?.status == .dismissed)
    #expect(undo.available(at: t0.addingTimeInterval(5.9)) == card)
    #expect(undo.available(at: t0.addingTimeInterval(6.1)) == nil, "after the window the suggestion is gone from the review view")

    #expect(undo.take(at: t0.addingTimeInterval(2)) == card)
    #expect(undo.available(at: t0.addingTimeInterval(2)) == nil, "taken once")
    try actions.restore(candidate)
    #expect(try store.candidates.fetch(candidate.id)?.status == .pending, "undo restores the card exactly")

    var queue = CardQueue()
    queue.apply(.candidates([candidate], segment: segments[0].id))
    queue.remove(card.id)
    queue.memoryDismissed(card.id)
    queue.restore(card)
    #expect(queue.cards == [card])
}

@Test func renameChangesTitleOnly() throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let actions = CandidateActions(store: store)
    let (_, segments) = try StoreFixtures.session(in: store.sessions)
    let out = MemoryOut(ref: "m1", kind: .event, title: "The pomegranate tree", quote: "the garden had a pomegranate tree", segmentSpan: WordSpan(startWord: 0, endWord: 5),
                        peopleRefs: [], placeText: nil, anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
    let candidate = StoreFixtures.candidate(segments[0].id, payload: try CandidatePayload.encode(out))
    try store.candidates.insert(candidate)
    let memory = try actions.acceptMemory(candidate).memory
    try actions.renameMemory(memory.id, to: "  Grandpa's tree ")
    let renamed = try #require(try store.memories.fetch(memory.id))
    #expect(renamed.title == "Grandpa's tree" && renamed.summaryQuote == memory.summaryQuote, "the quote is the owner's and never edited")
    #expect(throws: CandidateActions.Error.emptyTitle) { try actions.renameMemory(memory.id, to: "   ") }
}

@Test func linkAndUnlinkPerson() throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let actions = CandidateActions(store: store)
    let (_, segments) = try StoreFixtures.session(in: store.sessions)
    let out = MemoryOut(ref: "m1", kind: .event, title: "The pomegranate tree", quote: "pomegranate tree", segmentSpan: WordSpan(startWord: 4, endWord: 5),
                        peopleRefs: [], placeText: nil, anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
    let candidate = StoreFixtures.candidate(segments[0].id, payload: try CandidatePayload.encode(out))
    try store.candidates.insert(candidate)
    let memory = try actions.acceptMemory(candidate).memory
    let maya = try store.people.insertPerson(displayName: "Maya")
    try actions.linkPerson(maya.id, to: memory.id, roleText: "my sister")
    try actions.linkPerson(maya.id, to: memory.id, roleText: nil)
    #expect(try store.memories.people(of: memory.id).map(\.displayName) == ["Maya"], "a second link is a no-op")
    let newcomer = try actions.linkNewPerson(named: "Uncle Teo", to: memory.id)
    #expect(try store.memories.people(of: memory.id).map(\.displayName) == ["Maya", "Uncle Teo"] && newcomer.displayName == "Uncle Teo")
    try actions.unlinkPerson(maya.id, from: memory.id)
    #expect(try store.memories.people(of: memory.id).map(\.displayName) == ["Uncle Teo"])
    #expect(try store.people.person(id: maya.id) != nil, "unlinking never deletes the person")
}
