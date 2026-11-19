import Testing
import GRDB
@testable import LifelineKit

@Test func strongerOrigin() {
    #expect(LinkOrigin.stronger(.assumed, .confirmed) == .confirmed)
    #expect(LinkOrigin.stronger(.confirmed, .assumed) == .confirmed)
    #expect(LinkOrigin.stronger(.new, .assumed) == .assumed)
    #expect(LinkOrigin.stronger(.said, .assumed) == .said)
    #expect(LinkOrigin.stronger(nil, .new) == .new, "nil is weaker than every case, even new")
    #expect(LinkOrigin.stronger(.new, nil) == .new)
    #expect(LinkOrigin.stronger(nil, nil) == nil)
    #expect(LinkOrigin.stronger(.said, .said) == .said)
}

@Test func strengthOrdersConfirmedSaidAssumedNew() {
    #expect(LinkOrigin.allCases.sorted { $0.strength > $1.strength } == [.confirmed, .said, .assumed, .new])
}

@Test func aLinkRoundTripsItsOrigin() throws {
    let db = try AppDatabase.inMemory()
    try db.writer.write { db in
        try db.execute(sql: """
            insert into entity (id, type, title, created_at) values ('e1', 'person', 'Maya', '2026-10-01');
            insert into entity (id, type, title, created_at) values ('e2', 'person', 'Noor', '2026-10-01');
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01');
            """)
        try MomentEntity(memoryID: MemoryID(rawValue: "m1"), entityID: EntityID(rawValue: "e1"), relation: .mention,
                         roleText: "my sister", origin: .assumed, personHandle: "p1").insert(db)
        // The same write path the extractor uses.
        try MomentEntity(memoryID: MemoryID(rawValue: "m1"), entityID: EntityID(rawValue: "e2"), relation: .mention,
                         origin: .said, personHandle: "p2").insertIgnoringDuplicate(db)
    }
    let links = try db.writer.read { try MomentEntity.order(Column("entity_id")).fetchAll($0) }
    #expect(links.map(\.origin) == [.assumed, .said])
    #expect(links.map(\.personHandle) == ["p1", "p2"])
    #expect(links[0].roleText == "my sister")
}

@Test func aLinkWithoutAnOriginStaysNil() throws {
    let db = try AppDatabase.inMemory()
    try db.writer.write { db in
        try db.execute(sql: """
            insert into entity (id, type, title, created_at) values ('e1', 'person', 'Maya', '2026-10-01');
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01');
            """)
        try MemoryPerson(memoryID: MemoryID(rawValue: "m1"), personID: PersonID(rawValue: "e1"), roleText: nil).link.insertIgnoringDuplicate(db)
    }
    let link = try db.writer.read { try MomentEntity.fetchOne($0) }
    #expect(link?.origin == nil && link?.personHandle == nil)
    #expect(MemoryPerson(memoryID: MemoryID(rawValue: "m1"), personID: PersonID(rawValue: "e1"), roleText: nil, origin: .confirmed).link.origin == .confirmed)
}

@Test func aPersonRoundTripsItsContactFields() throws {
    let db = try AppDatabase.inMemory()
    var person = Person(id: PersonID(rawValue: "p1"), displayName: "Maya", notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                        nameOrigin: .contact, createdByGuess: true, contactIdentifier: "k1", contactName: "Maya R", contactState: "linked")
    try db.writer.write { try person.insertWithEntity($0) }
    let fetched = try db.writer.read { try Person.fetchOne($0, sql: Person.selectSQL + " where person.id = 'p1'") }
    #expect(fetched == person)
    person.contactIdentifier = nil
    person.createdByGuess = false
    try db.writer.write { try person.update($0) }
    #expect(try db.writer.read { try Person.fetchOne($0, sql: Person.selectSQL + " where person.id = 'p1'") } == person)
}
