import Foundation
import GRDB
import Testing
@testable import LifelineKit

/// Two places or things that are one (A2a): the merge moves everything, and the launch repair
/// joins the copies that "Ohio." beside "Ohio" left behind.
private struct Env {
    let db: AppDatabase, store: ExtractionStore, actions: CandidateActions
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = CandidateActions(store: store)
    }

    func kept(_ text: String) throws -> Memory {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        let words = text.split(separator: " ").count
        let out = MemoryOut(ref: "m1", kind: .event, title: text, quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return try actions.acceptMemory(c, joinStory: false).memory
    }

    /// Two rows for one name, as the old comparison left them. `insert` would reuse the first.
    func twins(_ type: EntityType, _ a: String, _ b: String) throws -> (Entity, Entity) {
        let first = Entity(type: type, title: a, createdAt: Date(timeIntervalSince1970: 1_000))
        let second = Entity(type: type, title: b, createdAt: Date(timeIntervalSince1970: 2_000))
        var write = EntityRepository.Write()
        write.entities = [first, second]
        try store.entities.apply(write)
        return (first, second)
    }

    func segment(of memory: Memory) throws -> SegmentID { try #require(try store.memories.spans(of: memory.id).first).segmentID }
}

@Test func mergeMovesLinksAndKeepsOneWhereBothHadIt() throws {
    let env = try Env()
    let (ohio, copy) = try env.twins(.place, "Ohio", "Ohio.")
    let a = try env.kept("we drove through the state"), b = try env.kept("the fair was that August"), c = try env.kept("the long road home")
    try env.store.entities.link(a.id, ohio.id, relation: .mention)
    try env.store.entities.link(b.id, copy.id, relation: .mention)
    try env.store.entities.link(c.id, ohio.id, relation: .mention)
    try env.store.entities.link(c.id, copy.id, relation: .mention)
    #expect(try env.store.entities.merge(copy.id, into: ohio.id))
    let links = try env.store.entities.links(to: ohio.id)
    #expect(Set(links.map(\.memoryID)) == Set([a.id, b.id, c.id]) && links.count == 3, "every memory once")
    #expect(try env.store.entities.entity(id: copy.id) == nil)
    #expect(try env.store.entities.entity(id: ohio.id)?.title == "Ohio", "the stored spelling of the one that stays")
}

@Test func mergeMovesFirstTellingsAfterTheTargetsOwnAndTags() throws {
    let env = try Env()
    let (ohio, copy) = try env.twins(.place, "Ohio", "Ohio.")
    let a = try env.kept("we drove through the state"), b = try env.kept("the fair was that August")
    try env.store.entities.insertSpan(EntitySpan(entityID: ohio.id, segmentID: try env.segment(of: a), startMs: 100, endMs: 200, order: 0))
    try env.store.entities.insertSpan(EntitySpan(entityID: copy.id, segmentID: try env.segment(of: b), startMs: 300, endMs: 400, order: 0))
    try env.store.tags.tag(.entity, ohio.id.rawValue, "home")
    try env.store.tags.tag(.entity, copy.id.rawValue, "home")
    try env.store.tags.tag(.entity, copy.id.rawValue, "travel")
    #expect(try env.store.entities.merge(copy.id, into: ohio.id))
    let spans = try env.store.entities.spans(of: ohio.id)
    #expect(spans.map(\.order) == [0, 1] && spans.map(\.startMs) == [100, 300], "the target's own telling stays first")
    #expect(Set(try env.store.tags.tags(of: .entity, ohio.id.rawValue)) == Set(["home", "travel"]))
    #expect(try env.store.tags.tags(of: .entity, copy.id.rawValue).isEmpty)
}

@Test func mergeNeverRevealsWhatWasPutAway() throws {
    let env = try Env()
    let (ohio, copy) = try env.twins(.place, "Ohio", "Ohio.")
    try env.store.entities.setHidden(copy.id, true)
    try env.store.entities.setExcluded(copy.id, true)
    #expect(try env.store.entities.merge(copy.id, into: ohio.id))
    let merged = try #require(try env.store.entities.entity(id: ohio.id))
    #expect(merged.hiddenFromTimeline && merged.excludedFromAI, "hidden or excluded on either side stays so")
}

@Test func mergeRefusesTheSameAMissingADifferentTypeAndPeople() throws {
    let env = try Env()
    let (ohio, copy) = try env.twins(.place, "Ohio", "Ohio.")
    let thing = try env.store.entities.insert(type: .thing, title: "Ohio")
    let sam = try env.store.people.insertPerson(displayName: "Sam"), other = try env.store.people.insertPerson(displayName: "Sam")
    #expect(try !env.store.entities.merge(ohio.id, into: ohio.id))
    #expect(try !env.store.entities.merge(EntityID(), into: ohio.id))
    #expect(try !env.store.entities.merge(copy.id, into: EntityID()))
    #expect(try !env.store.entities.merge(thing.id, into: ohio.id), "a thing is not a place")
    #expect(try !env.store.entities.merge(other.entityID, into: sam.entityID), "two people can share a name")
    #expect(try env.store.entities.entity(id: copy.id) != nil && (try env.store.people.person(id: other.id)) != nil)
}

@Test func theRepairJoinsPlacesWithOneNameAndLeavesTheRest() throws {
    let env = try Env()
    let (ohio, _) = try env.twins(.place, "Ohio", "Ohio.")
    _ = try env.store.entities.insert(type: .thing, title: "Ohio")
    _ = try env.store.entities.insert(type: .place, title: "Andover")
    _ = try env.store.people.insertPerson(displayName: "Sam")
    _ = try env.store.people.insertPerson(displayName: "Sam")
    let (belief, _) = try env.twins(.idea, "Say yes", "say yes")

    let report = try ArchiveRepair.run(env.store)
    #expect(report.joinedEntities == [StoryRepository.MergedTitle(title: "Ohio", copies: 2)])
    #expect(report.notice == "Joined 2 copies of “Ohio”.")
    #expect(try env.store.entities.entities(type: .place).map(\.id).contains(ohio.id))
    #expect(try env.store.entities.entities(type: .place).count == 2, "Ohio once, and Andover")
    #expect(try env.store.entities.entities(type: .thing).count == 1, "a thing named Ohio is not the place")
    #expect(try env.store.people.people().count == 2, "people are never joined by name")
    #expect(try env.store.entities.entities(type: .idea).count == 2 && (try env.store.entities.entity(id: belief.id)) != nil, "ideas are never joined by name")

    let again = try ArchiveRepair.run(env.store)
    #expect(again.joinedEntities.isEmpty && again.notice == nil, "a second run finds nothing to do")
}

@Test func theRepairJoinsCollectionsWithOneTitle() throws {
    let env = try Env()
    let a = try env.kept("we drove through the state"), b = try env.kept("the fair was that August"), c = try env.kept("the long road home")
    let trips = try env.store.chapters.insertCollection(titled: "Family trips")
    let copy = Collection(id: .init(), title: "family trips.")
    try env.db.writer.write { db in
        try copy.insert(db)
        for (collection, memory) in [(trips.id, a.id), (trips.id, b.id), (copy.id, b.id), (copy.id, c.id)] {
            try db.execute(sql: "insert into collection_memory (collection_id, memory_id) values (?, ?)", arguments: [collection.rawValue, memory.rawValue])
        }
    }
    let report = try ArchiveRepair.run(env.store)
    #expect(report.joinedCollections == [StoryRepository.MergedTitle(title: "Family trips", copies: 2)])
    #expect(try env.store.chapters.collections().map(\.id) == [trips.id])
    #expect(Set(try env.store.chapters.members(of: trips.id).map(\.id)) == Set([a.id, b.id, c.id]), "a memory in both stays once")
}

@Test func aRepairOfSeveralKindsGivesOneNotice() throws {
    let env = try Env()
    _ = try env.twins(.place, "Ohio", "Ohio.")
    let a = try env.kept("we packed the car"), b = try env.kept("the tire went flat")
    _ = try env.actions.createStory(title: "The road trip", containing: [a.id])
    _ = try env.actions.createStory(title: "The road trip", containing: [b.id])
    let report = try ArchiveRepair.run(env.store)
    #expect(report.joinedStories.count == 1 && report.joinedEntities.count == 1)
    #expect(report.notice == "Joined copies of 2 things that had the same name.")
}
