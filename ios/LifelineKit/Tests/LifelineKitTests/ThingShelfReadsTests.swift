import Foundation
import GRDB
import Testing
@testable import LifelineKit

// S7, Task 3: what the Things shelf reads, and how few statements it takes.

private func at(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 60) }

private func photo(_ name: String, at n: Int = 0) -> Photo {
    Photo(fileName: "\(name).jpg", sha256: "hash-\(name)", pixelWidth: 400, pixelHeight: 300, addedAt: at(n))
}

/// Counts the statements one connection runs.
private final class StatementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// A store with an owner born 1990-06-01 and one told memory per segment, each told a minute after the last.
private struct Fixture {
    let db: AppDatabase
    let store: ExtractionStore
    let sessionID: SessionID
    let segments: [Segment]
    private var next = 0

    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        (sessionID, segments) = try StoreFixtures.session(in: store.sessions, segments: (1...40).map { "we kept it in the shed, time \($0)" })
        let birth = Calendar.current.date(from: DateComponents(year: 1990, month: 6, day: 1))
        try store.profile.save(Profile(displayName: "Jordan", birthDate: birth, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    }

    func thing(_ title: String) throws -> Entity { try store.entities.insert(type: .thing, title: title) }

    /// A told memory of a kind, optionally linked to an entity, hidden or floating.
    mutating func memory(_ title: String, kind: MemoryKind = .fact, told n: Int? = nil, hidden: Bool = false, floating: Bool = false,
                         link entity: Entity? = nil, relation: EntityRelation = .detail) throws -> Memory {
        next += 1
        let made = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[next - 1].id, title: title, createdAt: at(n ?? next))
        if kind != .event { try store.memories.setKind(made.id, kind) }
        if hidden { try store.memories.setHidden(made.id, true) }
        if floating { try db.writer.write { try $0.execute(sql: "update memory set created_from_candidate_id = null where id = ?", arguments: [made.id.rawValue]) } }
        if let entity { try store.entities.link(made.id, entity.id, relation: relation, roleText: nil) }
        return made
    }
}

@Test func detailsAreReadForEveryEntityOfATypeOldestToldFirst() throws {
    var f = try Fixture()
    let bike = try f.thing("The red bike"), guitar = try f.thing("The guitar")
    _ = try f.memory("B", told: 2, link: bike)
    _ = try f.memory("A", told: 1, link: bike)
    _ = try f.memory("C", link: guitar)
    let details = try f.store.entities.details(type: .thing)
    #expect(details[bike.id]?.map(\.title) == ["A", "B"])
    #expect(details[guitar.id]?.map(\.title) == ["C"])
}

@Test func aHiddenOrUntoldDetailIsNotRead() throws {
    var f = try Fixture()
    let bike = try f.thing("The red bike")
    _ = try f.memory("Hidden fact", hidden: true, link: bike)
    _ = try f.memory("Stand-in", floating: true, link: bike)
    #expect(try f.store.entities.details(type: .thing)[bike.id] == nil)
}

@Test func aMentionIsNotADetail() throws {
    var f = try Fixture()
    let bike = try f.thing("The red bike")
    _ = try f.memory("We rode it", kind: .event, link: bike, relation: .mention)
    #expect(try f.store.entities.details(type: .thing)[bike.id] == nil)
}

@Test func detailsOfAnotherTypeAreNotRead() throws {
    var f = try Fixture()
    let maya = try f.store.people.insertPerson(displayName: "Maya")
    let entity = try #require(try f.store.entities.entity(id: maya.entityID))
    _ = try f.memory("Likes tea", link: entity)
    #expect(try f.store.entities.details(type: .thing).isEmpty)
}

@Test func theShelfSourceLeavesAHiddenThingAndItsKeyPhotoOut() throws {
    let f = try Fixture()
    let bike = try f.thing("The red bike"), box = try f.thing("The tin box")
    try f.store.photos.insert(photo("bike"), linkingTo: .entity(bike.id))
    try f.store.photos.insert(photo("box"), linkingTo: .entity(box.id))
    try f.store.entities.setHidden(box.id, true)
    let source = try f.store.thingShelfSource()
    #expect(source.things.map(\.entity.title) == ["The red bike"])
    #expect(Set(source.keyPhotos.keys) == [bike.id])
}

@Test func theShelfSourceLeavesAHiddenOrUntoldMemoryOut() throws {
    var f = try Fixture()
    let bike = try f.thing("The red bike")
    let shown = try f.memory("Shown", link: bike)
    let hidden = try f.memory("Hidden", hidden: true, link: bike)
    let standIn = try f.memory("Stand-in", floating: true, link: bike)
    let hiddenMoment = try f.memory("Hidden ride", kind: .event, hidden: true, link: bike, relation: .mention)
    // An untold stand-in moment with a year: it must not place the thing or count as a moment.
    let standInMoment = try f.memory("Stand-in ride", kind: .event, floating: true, link: bike, relation: .mention)
    try f.store.memories.updateRange(standInMoment.id, .stated(year: 1999))
    let source = try f.store.thingShelfSource()
    #expect(source.details[bike.id]?.map(\.id) == [shown.id])
    #expect(Set(source.tellings.keys) == [shown.id])
    for gone in [hidden.id, standIn.id, hiddenMoment.id, standInMoment.id] { #expect(source.tellings[gone] == nil) }
    #expect(source.things.first?.momentRanges.isEmpty == true)
}

@Test func theShelfSourceCarriesTheBirthYearTellingsAndHeavySessions() throws {
    var f = try Fixture()
    let bike = try f.thing("The red bike")
    let fact = try f.memory("Bell", link: bike)
    let source = try f.store.thingShelfSource()
    #expect(source.birthYear == 1990)
    #expect(source.tellings[fact.id]?.sessionID == f.sessionID)
    #expect(source.heavySessions.isEmpty)
}

@Test func theShelfSourceTellsEveryKindOfDetailFirstTelling() throws {
    var f = try Fixture()
    let bike = try f.thing("The red bike")
    let fact = try f.memory("Bell", kind: .fact, link: bike)
    let moment = try f.memory("Ride", kind: .event, link: bike, relation: .mention)
    let source = try f.store.thingShelfSource()
    #expect(source.tellings[fact.id] != nil)
    #expect(source.tellings[moment.id] != nil)
}

@Test func theShelfSourceReadsInAFixedNumberOfStatements() throws {
    var f = try Fixture()
    let counter = StatementCounter()
    try f.db.writer.write { db in db.trace { _ in counter.add() } }
    var made = 0
    func addThings(_ count: Int) throws {
        for _ in 0..<count {
            made += 1
            let thing = try f.thing("Thing \(made)")
            _ = try f.memory("fact \(made)", link: thing)
            _ = try f.memory("moment \(made)", kind: .event, link: thing, relation: .mention)
            try f.store.photos.insert(photo("p\(made)", at: made), linkingTo: .entity(thing.id))
        }
    }
    func statementsForOneRead() throws -> Int {
        let before = counter.count
        _ = try f.store.thingShelfSource()
        return counter.count - before
    }
    try addThings(2)
    let statementsFor2 = try statementsForOneRead()
    try addThings(18)
    let statementsFor20 = try statementsForOneRead()
    #expect(statementsFor2 > 0)
    #expect(statementsFor20 == statementsFor2)
}

@Test func theShelfSourceCarriesAHeavySession() throws {
    var f = try Fixture()
    let bike = try f.thing("The red bike")
    let heavy = Session(id: .init(), startedAt: at(500), endedAt: nil, audioPath: "heavy.m4a",
                        stageLog: #"[{"stage":"windDown","at":"2026-03-01T00:00:00Z","reason":"wantsToStop"}]"#, landingChoiceMade: true)
    try f.store.sessions.insert(heavy)
    let heavySegment = Segment(id: .init(), sessionID: heavy.id, index: 0, startMs: 0, endMs: 900, text: "words", status: .extracted)
    try f.store.sessions.insert(heavySegment, words: [])
    let heavyDetail = try StoreFixtures.memory(in: f.store.memories, candidates: f.store.candidates, segment: heavySegment.id, title: "Heavy", createdAt: at(1))
    try f.store.memories.setKind(heavyDetail.id, .fact)
    try f.store.entities.link(heavyDetail.id, bike.id, relation: .detail, roleText: nil)

    var source = try f.store.thingShelfSource()
    #expect(source.heavySessions == [heavy.id])
    #expect(source.tellings[heavyDetail.id]?.sessionID == heavy.id)
    func quote() -> String? {
        ThingQuote.choose(details: source.details[bike.id] ?? [], tellings: source.tellings, heavySessions: source.heavySessions)
    }
    #expect(quote() == nil, "the only detail was told in a heavy session")

    _ = try f.memory("Calm", told: 2, link: bike)
    source = try f.store.thingShelfSource()
    #expect(quote() == "The garden had a pomegranate tree")
}
