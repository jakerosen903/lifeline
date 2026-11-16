import Foundation
import Testing
@testable import LifelineKit

private func memory(_ segment: SegmentID, ordinal: Int, ref: String = "m", people: [String] = [], place: String? = nil,
                    refs: [EntityRefOut] = [], about: String? = nil) throws -> (Candidate, MemoryOut) {
    let out = MemoryOut(ref: ref, title: "T", quote: "q", segmentSpan: WordSpan(startWord: 0, endWord: 0), peopleRefs: people, placeText: place,
                        anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, entityRefs: refs, aboutRef: about)
    return (StoreFixtures.candidate(segment, ordinal: ordinal, kind: .memory, payload: try CandidatePayload.encode(out)), out)
}
private func entityCard(_ segment: SegmentID, text: String, kind: MentionKind, ref: String? = nil) throws -> Card {
    let out = MentionOut(text: text, kind: kind, likelyAliasOfPersonID: nil, confidence: 0.8, ref: ref)
    return .entity(StoreFixtures.candidate(segment, ordinal: 9, kind: .entity, payload: try CandidatePayload.encode(out)), out)
}
private func personCard(_ segment: SegmentID, text: String, ref: String? = nil) throws -> Card {
    let out = MentionOut(text: text, kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8, ref: ref)
    return .whoIsThis(.candidate(StoreFixtures.candidate(segment, ordinal: 9, kind: .person, payload: try CandidatePayload.encode(out))), text: text)
}
private func id(_ m: (Candidate, MemoryOut)) -> String { m.0.id.rawValue }

@Test func hintOwnedByItsMemoryID() {
    let hint = Card.hint(StoreFixtures.candidate(SegmentID(), kind: .hint, payload: "{}"), HintOut(kind: .story, phrase: "p", memoryCandidateID: "mem-1"))
    #expect(FollowUpOwner.owner(of: hint, among: [], excluding: []) == "mem-1")
    #expect(hint.isFollowUp)
}

@Test func hintWithExcludedMemoryHasNoOwner() {
    let hint = Card.hint(StoreFixtures.candidate(SegmentID(), kind: .hint, payload: "{}"), HintOut(kind: .story, phrase: "p", memoryCandidateID: "mem-1"))
    #expect(FollowUpOwner.owner(of: hint, among: [], excluding: ["mem-1"]) == nil)
}

@Test func entityOwnedByAboutRef() throws {
    let s = SegmentID()
    let m = try memory(s, ordinal: 0, about: "e1")
    #expect(FollowUpOwner.owner(of: try entityCard(s, text: "x", kind: .thing, ref: "e1"), among: [m], excluding: []) == id(m))
}

@Test func entityOwnedByEntityRefTextAndKind() throws {
    let s = SegmentID()
    let m = try memory(s, ordinal: 0, refs: [EntityRefOut(text: "the shed", kind: .thing, likelyEntityID: nil)])
    #expect(FollowUpOwner.owner(of: try entityCard(s, text: "The Shed", kind: .thing), among: [m], excluding: []) == id(m))
    #expect(FollowUpOwner.owner(of: try entityCard(s, text: "The Shed", kind: .place), among: [m], excluding: []) == nil)
}

@Test func placeOwnedByPlaceText() throws {
    let s = SegmentID()
    let m = try memory(s, ordinal: 0, place: "Lake House")
    #expect(FollowUpOwner.owner(of: try entityCard(s, text: "lake house", kind: .place), among: [m], excluding: []) == id(m))
}

@Test func personOwnedByPeopleRefs() throws {
    let s = SegmentID()
    let m = try memory(s, ordinal: 0, people: ["Theo"])
    let card = try personCard(s, text: " theo ")
    #expect(FollowUpOwner.owner(of: card, among: [m], excluding: []) == id(m))
    #expect(card.isFollowUp)
}

@Test func personOwnedByAboutRef() throws {
    let s = SegmentID()
    let m = try memory(s, ordinal: 0, about: "p1")
    #expect(FollowUpOwner.owner(of: try personCard(s, text: "Theo", ref: "p1"), among: [m], excluding: []) == id(m))
}

@Test func firstByOrdinalWins() throws {
    let s = SegmentID()
    let a = try memory(s, ordinal: 2, people: ["Theo"]), b = try memory(s, ordinal: 1, people: ["Theo"])
    #expect(FollowUpOwner.owner(of: try personCard(s, text: "Theo"), among: [a, b], excluding: []) == id(b))
}

@Test func excludedMemoryPassesToNext() throws {
    let s = SegmentID()
    let a = try memory(s, ordinal: 2, people: ["Theo"]), b = try memory(s, ordinal: 1, people: ["Theo"])
    #expect(FollowUpOwner.owner(of: try personCard(s, text: "Theo"), among: [a, b], excluding: [id(b)]) == id(a))
    #expect(FollowUpOwner.owner(of: try personCard(s, text: "Theo"), among: [a, b], excluding: [id(a), id(b)]) == nil)
}

@Test func otherSegmentDoesNotOwn() throws {
    let m = try memory(SegmentID(), ordinal: 0, people: ["Theo"])
    #expect(FollowUpOwner.owner(of: try personCard(SegmentID(), text: "Theo"), among: [m], excluding: []) == nil)
}

@Test func noReferenceMeansNoOwner() throws {
    let s = SegmentID()
    let m = try memory(s, ordinal: 0, people: ["Maya"])
    #expect(FollowUpOwner.owner(of: try personCard(s, text: "Theo"), among: [m], excluding: []) == nil)
    #expect(FollowUpOwner.owner(of: try entityCard(s, text: "shed", kind: .thing), among: [m], excluding: []) == nil)
}

@Test func memoryAndMentionRowAreNotFollowUps() throws {
    let s = SegmentID()
    let m = try memory(s, ordinal: 0)
    #expect(!Card.memory(m.0, m.1).isFollowUp)
}
