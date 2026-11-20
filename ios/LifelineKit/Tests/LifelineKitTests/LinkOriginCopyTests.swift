import Foundation
import GRDB
import Testing
@testable import LifelineKit

// R6: every write that copies a link carries its origin and handle, and on a key collision the
// row that stays keeps the stronger origin. A merge must never turn a marked guess into an unmarked link.

private struct Env {
    let db: AppDatabase, store: ExtractionStore, actions: CandidateActions
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = CandidateActions(store: store)
    }

    /// A kept memory in a session of its own (the fixture's card always takes ordinal 0).
    func kept(_ title: String) throws -> Memory {
        let segment = try StoreFixtures.session(in: store.sessions, segments: ["Robin and I painted the fence"]).1[0].id
        return try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segment, title: title)
    }

    func link(_ memory: MemoryID, _ entity: EntityID, _ relation: EntityRelation = .mention, origin: LinkOrigin?, handle: String? = nil) throws {
        try db.writer.write { db in
            try MomentEntity(memoryID: memory, entityID: entity, relation: relation, roleText: "Robin", origin: origin, personHandle: handle)
                .insertIgnoringDuplicate(db)
        }
    }

    func row(_ memory: MemoryID, _ entity: EntityID, _ relation: EntityRelation = .mention) throws -> MomentEntity? {
        try store.entities.links(of: memory).map(\.link).first { $0.entityID == entity && $0.relation == relation }
    }
}

@Test func aMemoryMergeKeepsAnAssumedOrigin() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    // One recording: a handle has no meaning in another recording, so a fold across recordings drops it (final review I2).
    let segments = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin and I painted the fence", "Robin held the ladder"]).1
    let target = try StoreFixtures.memory(in: env.store.memories, candidates: env.store.candidates, segment: segments[0].id, title: "The fence")
    let source = try StoreFixtures.memory(in: env.store.memories, candidates: env.store.candidates, segment: segments[1].id, title: "Painting day")
    try env.link(source.id, robin.entityID, origin: .assumed, handle: "h1")
    _ = try env.actions.merge(source.id, into: target.id)
    let row = try #require(try env.row(target.id, robin.entityID))
    #expect(row.origin == .assumed, "the guess keeps its mark")
    #expect(row.personHandle == "h1")
}

@Test func aConfirmedRowMeetingAnAssumedRowStaysConfirmed() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    // Either side may hold the stronger origin.
    for (onTarget, onSource) in [(LinkOrigin.confirmed, LinkOrigin.assumed), (.assumed, .confirmed)] {
        let target = try env.kept("The fence"), source = try env.kept("Painting day")
        try env.link(target.id, robin.entityID, origin: onTarget)
        try env.link(source.id, robin.entityID, origin: onSource)
        _ = try env.actions.merge(source.id, into: target.id)
        #expect(try env.row(target.id, robin.entityID)?.origin == .confirmed, "\(onTarget) on the target, \(onSource) on the source")
    }
}

@Test func unmergeRestoresTheOriginAndHandle() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let target = try env.kept("The fence"), source = try env.kept("Painting day")
    try env.link(target.id, robin.entityID, origin: .confirmed)
    try env.link(source.id, robin.entityID, origin: .assumed, handle: "h2")
    let receipt = try env.actions.merge(source.id, into: target.id)
    try env.actions.unmerge(receipt)
    #expect(try env.row(target.id, robin.entityID)?.origin == .confirmed)
    let back = try #require(try env.row(source.id, robin.entityID))
    #expect(back.origin == .assumed && back.personHandle == "h2")
}

@Test func aKindChangeCarriesTheOriginBothWays() throws {
    let env = try Env()
    let devon = try env.store.people.insertPerson(displayName: "Devon")
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let memory = try env.kept("We were close")
    try env.store.memories.setKind(memory.id, .feeling)
    // Devon is both mentioned and described; Robin is only described.
    try env.link(memory.id, devon.entityID, .detail, origin: .confirmed)
    try env.link(memory.id, devon.entityID, .mention, origin: .assumed)
    try env.link(memory.id, robin.entityID, .detail, origin: .assumed, handle: "h3")
    let receipt = try env.store.memories.setKind(memory.id, .event)
    #expect(try env.row(memory.id, devon.entityID)?.origin == .confirmed, "the stronger origin survives the collision")
    let robinRow = try #require(try env.row(memory.id, robin.entityID))
    #expect(robinRow.origin == .assumed && robinRow.personHandle == "h3")
    try env.store.memories.undoKind(receipt)
    #expect(try env.row(memory.id, devon.entityID, .detail)?.origin == .confirmed)
    let robinDetail = try #require(try env.row(memory.id, robin.entityID, .detail))
    #expect(robinDetail.origin == .assumed && robinDetail.personHandle == "h3")
}

@Test func anEntityMergeKeepsTheStrongerOrigin() throws {
    let env = try Env()
    let fence = try env.store.entities.insert(type: .thing, title: "the fence")
    let copy = try env.store.entities.insert(type: .thing, title: "the old fence")
    let memory = try env.kept("The fence")
    try env.link(memory.id, fence.id, origin: .assumed)
    try env.link(memory.id, copy.id, origin: .said)
    #expect(try env.store.entities.merge(copy.id, into: fence.id))
    #expect(try env.row(memory.id, fence.id)?.origin == .said)
}
