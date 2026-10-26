import Foundation
import GRDB
import Testing
@testable import LifelineKit

// M7, PR B: people are entities. One link table; no parallel path.

@Test func noKitSourceReadsTheOldLinkTables() throws {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/LifelineKit")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)).compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Migrations.swift" }
    #expect(files.count > 50, "the walk found the kit's sources")
    let forbidden = ["memory_person", "memory_place", "from place ", "join place ", "into place (", "update place set", "person.display_name"]
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        for word in forbidden {
            #expect(!text.contains(word), "\(file.lastPathComponent) still uses \(word)")
        }
    }
}

@Test func renameMergeDeleteFollowTheEntity() throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    let actions = CandidateActions(store: store)
    let (session, _) = try StoreFixtures.session(in: store.sessions, segments: ["Maya climbed the wall", "Maya again at the wall"])
    let segments = try store.sessions.segments(in: session)
    let maya = try store.people.insertPerson(displayName: "Maya")
    #expect(try store.entities.entity(id: maya.entityID)?.type == .person, "the entity row is written with the person")
    #expect(try store.entities.entity(id: maya.entityID)?.title == "Maya")

    try store.people.rename(maya.id, to: "Mai")
    #expect(try store.entities.entity(id: maya.entityID)?.title == "Mai", "the name lives on the entity")
    #expect(try store.people.person(id: maya.id)?.displayName == "Mai")
    #expect(try store.people.findPerson(matching: "maya")?.id == maya.id, "the old name stays an alias")

    let a = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[0].id, title: "The wall")
    let b = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[1].id, title: "The wall again")
    try store.memories.link(maya.id, to: b.id, roleText: "my sister")
    let lisbon = try store.people.insertPlace(nameText: "Lisbon")
    try store.memories.insertPlace(MemoryPlace(memoryID: b.id, placeID: lisbon.id))
    #expect(try store.entities.links(of: b.id).count == 2)

    let receipt = try actions.merge(b.id, into: a.id)
    #expect(try store.memories.people(of: a.id).map(\.id) == [maya.id], "Same story carries the person link")
    #expect(try store.memories.places(of: a.id).map(\.nameText) == ["Lisbon"], "and the place link")
    #expect(try store.entities.links(of: a.id).first { $0.entity.id == maya.entityID }?.link.roleText == "my sister")

    try actions.unmerge(receipt)
    #expect(try store.memories.people(of: b.id).map(\.id) == [maya.id], "undo gives the links back to the memory they left")
    #expect(try store.memories.places(of: b.id).map(\.id) == [lisbon.id])
    #expect(try store.memories.people(of: a.id).isEmpty)

    try store.memories.delete(b.id)
    #expect(try store.entities.links(to: maya.entityID).isEmpty, "a deleted memory takes its links")
    #expect(try store.people.person(id: maya.id) != nil, "and leaves the person")
}

@Test func ownerIsAnEntity() throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    try store.profile.save(Profile(displayName: "Sam", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let owner = try #require(try store.profile.owner())
    #expect(try store.entities.entity(id: owner.entityID)?.title == "Sam")
    try store.profile.save(Profile(displayName: "Samira", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    #expect(try store.people.people().filter(\.isOwner).map(\.displayName) == ["Samira"], "still one owner, renamed on the entity")
}
