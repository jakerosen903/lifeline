import Foundation
import GRDB
import Testing
@testable import LifelineKit

// Task 4: the read model the views use. A link carries its origin, its person and its group.

private struct Env {
    let db: AppDatabase, store: ExtractionStore
    init() throws { db = try AppDatabase.inMemory(); store = ExtractionStore(db) }

    func session(segments: Int = 1) throws -> (SessionID, [Segment]) {
        try StoreFixtures.session(in: store.sessions, segments: (0..<segments).map { "text \($0) about the fence" })
    }

    /// A kept memory with one span (order 0) over the segment. Each gets its own candidate ordinal.
    func memory(in segment: SegmentID, title: String = "A title", createdAt: Date = .now) throws -> Memory {
        let ordinal = try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from candidate where segment_id = ?", arguments: [segment.rawValue]) ?? 0 }
        let candidate = StoreFixtures.candidate(segment, ordinal: ordinal)
        try store.candidates.insert(candidate)
        var memory = StoreFixtures.memory(from: candidate.id, title: title)
        memory.createdAt = createdAt
        try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment, startMs: 0, endMs: 1000, order: 0)],
                                  people: [], places: [], anchors: [])
        return memory
    }

    func link(_ memory: Memory, _ person: Person, said: String?, origin: LinkOrigin?, relation: EntityRelation = .mention) throws {
        try store.entities.link(memory.id, person.entityID, relation: relation, roleText: said, origin: origin)
    }

    func owner() throws -> Person {
        let owner = try store.people.insertPerson(displayName: "Sam Reyes")
        try db.writer.write { try $0.execute(sql: "update person set is_owner = 1 where id = ?", arguments: [owner.id.rawValue]) }
        return try #require(try store.people.person(id: owner.id))
    }
}

@Test func theGroupIsTheSameNameAndPersonInOneSession() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin Okafor")
    let other = try env.store.people.insertPerson(displayName: "Robin Vance")
    let (_, segs) = try env.session()
    let (_, elsewhere) = try env.session()
    let m1 = try env.memory(in: segs[0].id), m2 = try env.memory(in: segs[0].id), m3 = try env.memory(in: segs[0].id)
    let sameWords = try env.memory(in: segs[0].id)     // "robin " with other case and spaces
    let otherPerson = try env.memory(in: segs[0].id)
    let otherSession = try env.memory(in: elsewhere[0].id)
    for m in [m1, m2, m3] { try env.link(m, robin, said: "Robin", origin: .assumed) }
    try env.link(sameWords, robin, said: " robin ", origin: .assumed)
    try env.link(otherPerson, other, said: "Robin", origin: .assumed)
    try env.link(otherSession, robin, said: "Robin", origin: .assumed)

    let links = try env.store.personLinks.links(of: m1.id)
    let group = try env.store.personLinks.group(of: #require(links.first))
    #expect(Set(group.map(\.memoryID)) == Set([m1, m2, m3, sameWords].map(\.id)))
    #expect(group.contains { $0.id == links[0].id }, "the group includes the link itself")
}

@Test func aLinkWithNoSaidNameIsAGroupOfOne() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin Okafor")
    let (_, segs) = try env.session()
    let a = try env.memory(in: segs[0].id), b = try env.memory(in: segs[0].id), c = try env.memory(in: segs[0].id)
    try env.link(a, robin, said: nil, origin: .said)
    try env.link(b, robin, said: "  ", origin: .said)
    try env.link(c, robin, said: nil, origin: .said)
    for m in [a, b, c] {
        let link = try #require(try env.store.personLinks.links(of: m.id).first)
        #expect(try env.store.personLinks.group(of: link).map(\.memoryID) == [m.id])
    }
}

@Test func theSessionOfAMemoryIsThatOfItsFirstSpan() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin Okafor")
    let (_, first) = try env.session()
    let (_, second) = try env.session()
    let a = try env.memory(in: first[0].id), b = try env.memory(in: second[0].id)
    // a's later span (order 1) is in the other session; its first span still decides.
    try env.db.writer.write { db in
        try db.execute(sql: "insert into memory_span (memory_id, segment_id, start_ms, end_ms, \"order\") values (?, ?, 0, 100, 1)",
                       arguments: [a.id.rawValue, second[0].id.rawValue])
    }
    try env.link(a, robin, said: "Robin", origin: .assumed)
    try env.link(b, robin, said: "Robin", origin: .assumed)
    let link = try #require(try env.store.personLinks.links(of: a.id).first)
    #expect(try env.store.personLinks.group(of: link).map(\.memoryID) == [a.id])
}

@Test func guessCountCountsAssumedOnly() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin Okafor")
    let maya = try env.store.people.insertPerson(displayName: "Maya Lindqvist")
    let (session, segs) = try env.session()
    let (otherSession, elsewhere) = try env.session()
    let m1 = try env.memory(in: segs[0].id), m2 = try env.memory(in: segs[0].id), m3 = try env.memory(in: segs[0].id)
    let away = try env.memory(in: elsewhere[0].id)
    try env.link(m1, robin, said: "Robin", origin: .assumed)
    try env.link(m1, maya, said: "Maya", origin: .assumed)          // a second guess in one memory counts too
    try env.link(m2, robin, said: "Robin", origin: .said)
    try env.link(m2, maya, said: "Maya", origin: .confirmed)
    try env.link(m3, robin, said: nil, origin: .new)
    try env.link(m3, maya, said: nil, origin: nil)
    try env.link(m3, maya, said: "Maya", origin: .assumed, relation: .detail)   // a detail, not a mention
    try env.link(away, robin, said: "Robin", origin: .assumed)
    #expect(try env.store.personLinks.guessCount(in: session) == 2)
    #expect(try env.store.personLinks.guessCount(in: otherSession) == 1)
}

// PC-b Task 5: the landing asks for contacts once a kept moment of its recording names a person.
@Test func keptPeopleCountCountsMentionsOfOthersInTheSession() throws {
    let env = try Env()
    let owner = try env.owner()
    let robin = try env.store.people.insertPerson(displayName: "Robin Okafor")
    let maya = try env.store.people.insertPerson(displayName: "Maya Lindqvist")
    let (session, segs) = try env.session()
    let (otherSession, elsewhere) = try env.session()
    let (emptySession, _) = try env.session()
    let m1 = try env.memory(in: segs[0].id), m2 = try env.memory(in: segs[0].id)
    let away = try env.memory(in: elsewhere[0].id)
    try env.link(m1, robin, said: "Robin", origin: .new)
    try env.link(m1, maya, said: "Maya", origin: .assumed)
    try env.link(m2, robin, said: "Robin", origin: nil)                         // an older link counts too
    try env.link(m2, owner, said: "I", origin: .said)                           // the owner is not a person to match
    try env.link(m2, maya, said: "Maya", origin: .assumed, relation: .detail)   // a detail, not a mention
    try env.link(away, robin, said: "Robin", origin: .assumed)
    #expect(try env.store.personLinks.keptPeopleCount(in: session) == 3)
    #expect(try env.store.personLinks.keptPeopleCount(in: otherSession) == 1)
    #expect(try env.store.personLinks.keptPeopleCount(in: emptySession) == 0)
}

@Test func anOlderLinkReadsWithNoOrigin() throws {
    let env = try Env()
    let maya = try env.store.people.insertPerson(displayName: "Maya Lindqvist")
    let (_, segs) = try env.session()
    let m = try env.memory(in: segs[0].id)
    try env.link(m, maya, said: "Maya", origin: nil)
    let link = try #require(try env.store.personLinks.links(of: m.id).first)
    #expect(link.origin == nil)
    #expect(link.isGuess == false)
    #expect(link.saidName == "Maya")
    #expect(link.person.id == maya.id)
}

@Test func aMemorysLinksIncludeTheOwnerAndSkipPlacesAndDetails() throws {
    let env = try Env()
    let owner = try env.owner()
    let zed = try env.store.people.insertPerson(displayName: "Zed Park")
    let amy = try env.store.people.insertPerson(displayName: "Amy Ng")
    let (_, segs) = try env.session()
    let m = try env.memory(in: segs[0].id)
    try env.link(m, zed, said: "Zed", origin: .said)
    try env.link(m, owner, said: "me", origin: .confirmed)
    try env.link(m, amy, said: "Amy", origin: .assumed)
    try env.link(m, amy, said: "Amy", origin: .assumed, relation: .detail)
    let place = try env.store.entities.insert(type: .place, title: "The lake")
    try env.store.entities.link(m.id, place.id, relation: .mention)
    let links = try env.store.personLinks.links(of: m.id)
    #expect(links.map(\.person.id).contains(owner.id), "today's memory page shows the owner")
    #expect(links.map(\.person.displayName) == links.map(\.person.displayName).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    #expect(Set(links.map(\.person.id)) == Set([zed.id, owner.id, amy.id]))
    #expect(links.allSatisfy { $0.relation == .mention })
}

@Test func aPersonsLinksCoverBothRelations() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin Okafor")
    let (_, segs) = try env.session()
    let a = try env.memory(in: segs[0].id), b = try env.memory(in: segs[0].id)
    try env.link(a, robin, said: "Robin", origin: .assumed)
    try env.link(b, robin, said: "Robin", origin: .confirmed, relation: .detail)
    let links = try env.store.personLinks.links(to: robin.id)
    #expect(Set(links.map(\.memoryID)) == Set([a.id, b.id]))
    #expect(Set(links.map(\.relation)) == [.mention, .detail])
    #expect(links.first { $0.memoryID == a.id }?.isGuess == true)
}
