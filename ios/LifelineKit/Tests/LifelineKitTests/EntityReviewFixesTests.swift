import Foundation
import GRDB
import Testing
@testable import LifelineKit

// Review of PR #11: what leaves the device, and writes that must land together.

private struct Env {
    let store: ExtractionStore, actions: CandidateActions, segment: Segment
    init(_ text: String = "the house had a blue door in Lisbon") throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
        let (session, _) = try StoreFixtures.session(in: store.sessions, segments: [text])
        segment = try store.sessions.segments(in: session)[0]
    }
    func card(_ out: MemoryOut, ordinal: Int = 0) throws -> Candidate {
        let c = StoreFixtures.candidate(segment.id, ordinal: ordinal, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return c
    }
    func memoryOut(_ kind: MemoryKind, place: String? = nil, refs: [EntityRefOut] = []) -> MemoryOut {
        MemoryOut(ref: "m1", kind: kind, title: "Blue door", quote: "the house had a blue door", segmentSpan: WordSpan(startWord: 0, endWord: 5),
                  peopleRefs: [], placeText: place, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, entityRefs: refs)
    }
}

@Test func packetSkipsADetailExcludedFromAI() throws {
    let env = try Env()
    let kept = try env.actions.acceptMemory(try env.card(env.memoryOut(.fact)))
    let house = try env.store.entities.insert(type: .thing, title: "the house")
    try env.store.entities.link(kept.memory.id, house.id, relation: .detail)
    #expect(try ExtractionQueue.packetEntities(env.store).first { $0.0.id == house.id }?.1 == "the house had a blue door")
    try env.store.memories.setExcluded(kept.memory.id, true)
    let entry = try #require(try ExtractionQueue.packetEntities(env.store).first { $0.0.id == house.id })
    #expect(entry.1 == nil, "an excluded memory's words never ride along as an entity's detail")
    try env.store.memories.setExcluded(kept.memory.id, false)
    try env.store.memories.setHidden(kept.memory.id, true)
    #expect(try ExtractionQueue.packetEntities(env.store).first { $0.0.id == house.id }?.1 == nil, "nor a hidden one's")
}

@Test func anEntityWriteIsAllOrNothing() throws {
    let env = try Env()
    let card = StoreFixtures.candidate(env.segment.id, ordinal: 1, kind: .entity, payload: "{}")
    try env.store.candidates.insert(card)
    var plan = EntityRepository.Write()
    let shed = Entity(type: .thing, title: "the shed")
    plan.entities = [shed]
    plan.links = [MomentEntity(memoryID: MemoryID(), entityID: shed.id, relation: .mention)]   // no such memory: the write fails
    plan.acceptingCandidate = card.id
    #expect(throws: (any Error).self) { try env.store.entities.apply(plan) }
    #expect(try env.store.entities.entity(id: shed.id) == nil, "the entity does not land without its link")
    #expect(try env.store.candidates.fetch(card.id)?.status == .pending, "and the card stays as it was")
}

@Test func keepingAnEntityCardTwiceIsRefusedAndMakesOneEntity() throws {
    let env = try Env("I always believed hard work was everything")
    let out = MentionOut(text: "hard work was everything", kind: .idea, likelyAliasOfPersonID: nil, confidence: 0.8, ref: "i1", title: nil)
    let card = StoreFixtures.candidate(env.segment.id, ordinal: 1, kind: .entity, payload: try CandidatePayload.encode(out))
    try env.store.candidates.insert(card)
    let idea = try env.actions.acceptEntity(card)
    #expect(throws: CandidateActions.Error.notPending) { try env.actions.acceptEntity(card) }
    #expect(try env.store.entities.entities(type: .idea).map(\.id) == [idea.id])
    #expect(try env.store.entities.spans(of: idea.id).count == 1)
}

@Test func aPlaceFromTheChipsGetsAFirstTelling() throws {
    let env = try Env()
    let kept = try env.actions.acceptMemory(try env.card(env.memoryOut(.event, place: "Lisbon", refs: [EntityRefOut(text: "the house", kind: .thing, likelyEntityID: nil)])))
    let lisbon = try #require(try env.store.entities.find(type: .place, title: "Lisbon"))
    let house = try #require(try env.store.entities.find(type: .thing, title: "the house"))
    let primary = try #require(try env.store.memories.spans(of: kept.memory.id).first)
    for entity in [lisbon, house] {
        let span = try #require(try env.store.entities.spans(of: entity.id).first, "\(entity.title) can play its first telling")
        #expect(span.startMs == primary.startMs && span.endMs == primary.endMs)
    }
}

@Test func twoSegmentsNamingANewThingPlanOneEntity() {
    var a = EntityRepository.Write()
    let first = Entity(type: .thing, title: "the house")
    a.entities = [first]
    var b = EntityRepository.Write()
    let second = Entity(type: .thing, title: "The House")
    let memory = MemoryID()
    b.entities = [second]
    b.links = [MomentEntity(memoryID: memory, entityID: second.id, relation: .mention)]
    let remap = a.merge(b)
    #expect(a.entities.map(\.id) == [first.id])
    #expect(remap[second.id] == first.id && a.links.map(\.entityID) == [first.id])
}

@Test func aKindChangeMovesItsLinksInTheSameWrite() throws {
    let env = try Env()
    let kept = try env.actions.acceptMemory(try env.card(env.memoryOut(.fact)))
    let house = try env.store.entities.insert(type: .thing, title: "the house")
    try env.store.entities.link(kept.memory.id, house.id, relation: .detail)
    try env.store.memories.setKind(kept.memory.id, .event)   // the repository write alone, no follow-up
    #expect(try env.store.entities.links(of: kept.memory.id).map(\.link.relation) == [.mention])
}
