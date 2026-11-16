import Foundation
import GRDB
import Testing
@testable import LifelineKit

// S2, Task 1: one query per list, not one per entity.

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }

private func said(_ year: Int) -> TimeRange { .year(year, origin: .stated, evidence: nil) }

private func at(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 60) }

/// Counts the statements one connection runs.
private final class StatementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// A small store with an owner and a sentence of memories, each told a minute after the last.
private struct Fixture {
    let db: AppDatabase
    let store: ExtractionStore
    /// One segment per memory: a segment holds one candidate at a time.
    let segments: [Segment]
    private var next = 0

    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        let (_, segments) = try StoreFixtures.session(in: store.sessions, segments: (1...10).map { "we were all at the house, time \($0)" })
        self.segments = segments
        try store.profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    }

    var owner: Person { get throws { try #require(try store.profile.owner()) } }

    /// A told memory of a kind, in a year (nil: undated), hidden or not.
    mutating func memory(_ title: String, kind: MemoryKind = .event, year: Int? = nil, hidden: Bool = false) throws -> Memory {
        next += 1
        let made = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[next - 1].id, title: title, createdAt: at(next))
        if kind != .event { try store.memories.setKind(made.id, kind) }
        if let year { try store.memories.updateRange(made.id, said(year)) }
        if hidden { try store.memories.setHidden(made.id, true) }
        return made
    }

    /// A stand-in the person has not told: it has no candidate.
    mutating func floating(_ title: String) throws -> Memory {
        let made = try memory(title)
        try db.writer.write { try $0.execute(sql: "update memory set created_from_candidate_id = null where id = ?", arguments: [made.id.rawValue]) }
        return made
    }

    func person(_ name: String) throws -> Entity { try store.people.insertPerson(displayName: name).entity(in: store) }

    func link(_ memory: Memory, _ entities: Entity..., relation: EntityRelation = .mention, roleText: String? = nil) throws {
        for entity in entities { try store.entities.link(memory.id, entity.id, relation: relation, roleText: roleText) }
    }
}

private extension Person {
    func entity(in store: ExtractionStore) throws -> Entity { try #require(try store.entities.entity(id: entityID)) }
}

@Test func stripsReadEveryEntityOfATypeAtOnce() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad"), lena = try f.person("Lena")
    let m1 = try f.memory("Lake", year: 1999), m2 = try f.memory("Supper"), d1 = try f.memory("Likes tea", kind: .fact, year: 1995)
    try f.link(m1, maya, dad)
    try f.link(m2, maya)
    try f.link(d1, maya, relation: .detail)

    let strips = try f.store.entities.strips(type: .person)
    #expect(strips[maya.id]?.count == 3)
    #expect(strips[maya.id]?.filter(\.isMoment).map(\.memoryID) == [m1.id, m2.id])
    #expect(strips[dad.id]?.map(\.memoryID) == [m1.id])
    #expect(strips[lena.id] == nil)
}

@Test func aMemoryLinkedTwiceIsOneLinkedTime() throws {
    var f = try Fixture()
    let maya = try f.person("Maya")
    let m1 = try f.memory("Lake", year: 1999)
    try f.link(m1, maya)
    try f.link(m1, maya, relation: .detail)
    #expect(try f.store.entities.strips(type: .person)[maya.id]?.map(\.memoryID) == [m1.id])
    #expect(try f.store.entities.strips(type: .person)[maya.id]?.first?.isMoment == true)
}

@Test func theBatchedSpanEqualsThePerEntitySpan() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad"), lena = try f.person("Lena")
    let m1 = try f.memory("Lake", year: 1999), m2 = try f.memory("Supper"), d1 = try f.memory("Likes tea", kind: .fact, year: 1995)
    let m3 = try f.memory("Wedding")
    try f.store.memories.updateRange(m3.id, TimeRange(earliest: d("2003-01-01"), latest: d("2003-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: "around then"))
    try f.link(m1, maya, dad)
    try f.link(m2, maya)
    try f.link(d1, maya, relation: .detail)
    try f.link(m3, dad)

    let strips = try f.store.entities.strips(type: .person)
    for person in try f.store.entities.entities(type: .person) {
        #expect(EntityRepository.derivedSpan(over: strips[person.id, default: []].map(\.range)) == (try f.store.entities.derivedSpan(of: person.id)))
    }
    #expect(strips[lena.id] == nil)
    #expect(EntityRepository.derivedSpan(over: strips[dad.id, default: []].map(\.range)).origin == .inferred, "a guess in the span makes the span a guess")
}

@Test func hiddenAndUntoldMemoriesAreNotMoments() throws {
    var f = try Fixture()
    let maya = try f.person("Maya")
    let hidden = try f.memory("Hidden", year: 2001, hidden: true)
    let standIn = try f.floating("Stand-in")
    let fact = try f.memory("Likes tea", kind: .fact, year: 1995)
    try f.link(hidden, maya)
    try f.link(standIn, maya)
    try f.link(fact, maya)

    #expect(try f.store.entities.strips(type: .person)[maya.id]!.filter(\.isMoment).isEmpty)
    #expect(try f.store.entities.summaries(type: .person).first { $0.entity.id == maya.id }?.momentCount == 0)
}

@Test func coOccurrencesCountSharedMomentsAndNeedTwo() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad"), sam = try f.person("Sam")
    let street = try f.store.entities.insert(type: .place, title: "Alder Street")
    let work = try f.store.entities.insert(type: .idea, title: "hard work")
    let m1 = try f.memory("A"), m2 = try f.memory("B"), m3 = try f.memory("C"), m4 = try f.memory("D")
    try f.link(m1, maya, dad, street, work)
    try f.link(m2, maya, dad, street, work)
    try f.link(m3, maya, dad)
    try f.link(m4, maya, sam)

    #expect(try f.store.entities.coOccurrences(of: maya.id).map { "\($0.entity.title) \($0.sharedMoments)" } == ["Dad 3", "Alder Street 2"])
    #expect(try f.store.entities.coOccurrences(of: maya.id, minimumShared: 1).map(\.entity.title) == ["Dad", "Alder Street", "Sam"],
            "a lower minimum lets the one-off in, and ideas stay out")
}

@Test func theOwnerIsNeverOftenWith() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), owner = try f.owner
    let ownerEntity = try #require(try f.store.entities.entity(id: owner.entityID))
    for title in ["A", "B", "C"] { try f.link(try f.memory(title), maya, ownerEntity) }
    #expect(try !f.store.entities.coOccurrences(of: maya.id).contains { $0.entity.id == owner.entityID })
}

@Test func hiddenMemoriesAreNotShared() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), sam = try f.person("Sam")
    let told = try f.memory("A")
    let hiddenOne = try f.memory("B", hidden: true), hiddenTwo = try f.memory("C", hidden: true)
    let standIn = try f.floating("D")
    let fact = try f.memory("E", kind: .fact)
    for memory in [told, hiddenOne, hiddenTwo, standIn, fact] { try f.link(memory, maya, sam) }
    #expect(try !f.store.entities.coOccurrences(of: maya.id).contains { $0.entity.id == sam.id })
}

@Test func aHiddenEntityIsNotOftenWith() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), sam = try f.person("Sam")
    for title in ["A", "B"] { try f.link(try f.memory(title), maya, sam) }
    try f.store.entities.setHidden(sam.id, true)
    #expect(try f.store.entities.coOccurrences(of: maya.id).isEmpty)
}

@Test func ownWordsPreferARelationAliasThenTheCommonestRoleText() {
    #expect(OwnWords.choose(title: "Maya", aliases: ["Maya-bird", "my sister"], roleTexts: ["Maya"]) == "my sister")
    #expect(OwnWords.choose(title: "Dad", aliases: [], roleTexts: ["Dad", "my dad", "my dad", "he"]) == "my dad")
    #expect(OwnWords.choose(title: "Sam", aliases: [], roleTexts: ["sam ", "she", "Them"]) == nil)
    #expect(OwnWords.choose(title: "Lena", aliases: [], roleTexts: []) == nil)
    #expect(OwnWords.choose(title: "Ines", aliases: [], roleTexts: ["my friend", "our neighbour"]) == "my friend", "a tie goes to the alphabetically first")
}

@Test func ownWordsAreReadForWholeTypesAndForOne() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad"), lena = try f.person("Lena")
    try f.store.people.addAlias("my sister", to: PersonID(rawValue: maya.id.rawValue))
    try f.link(try f.memory("A"), dad, roleText: "my dad")
    try f.link(try f.memory("B"), dad, roleText: "my dad")
    try f.link(try f.memory("C"), dad, roleText: "Dad")

    #expect(try f.store.entities.ownWords(type: .person) == [maya.id: "my sister", dad.id: "my dad"], "the owner and Lena have none")
    #expect(try f.store.entities.ownWords(of: dad.id) == "my dad")
    #expect(try f.store.entities.ownWords(of: lena.id) == nil)
}

@Test func summariesCarryCountsFirstDatesAndOwnWords() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), lena = try f.person("Lena")
    try f.store.people.addAlias("my sister", to: PersonID(rawValue: maya.id.rawValue))
    try f.link(try f.memory("A", year: 2003), maya)
    try f.link(try f.memory("B", year: 1999), maya)
    try f.link(try f.memory("C"), maya)
    try f.link(try f.memory("Likes tea", kind: .fact, year: 1980), maya, relation: .detail)

    let summaries = try f.store.entities.summaries(type: .person)
    let mayaSummary = try #require(summaries.first { $0.entity.title == "Maya" })
    #expect(mayaSummary.momentCount == 3, "an undated moment still counts")
    #expect(mayaSummary.momentRanges.map(\.isPlaced) == [true, true, false], "oldest told first, unplaced included")
    #expect(mayaSummary.firstDate?.year == 1999 && mayaSummary.ownWords == "my sister")
    #expect(mayaSummary.span.earliest?.year == 1980, "the derived span takes the detail too")
    let lenaSummary = try #require(summaries.first { $0.entity.id == lena.id })
    #expect(lenaSummary.momentCount == 0 && lenaSummary.firstDate == nil && !lenaSummary.span.isPlaced)
    #expect(summaries.map(\.entity.title) == summaries.map(\.entity.title).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
}

@Test func aStatedSpanBeatsTheDerivedOne() throws {
    var f = try Fixture()
    let maya = try f.person("Maya")
    try f.link(try f.memory("A", year: 2003), maya)
    let stated = TimeRange(earliest: d("1990-01-01"), latest: d("2001-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .stated, evidenceText: "1990 to 2001")
    try f.store.entities.setStatedSpan(maya.id, stated)
    #expect(try f.store.entities.summaries(type: .person).first { $0.entity.id == maya.id }?.span == stated)
}

@Test func summariesLeaveHiddenEntitiesOut() throws {
    let f = try Fixture()
    let maya = try f.person("Maya"), sam = try f.person("Sam")
    try f.store.entities.setHidden(sam.id, true)
    #expect(try f.store.entities.summaries(type: .person).map(\.entity.id).contains(sam.id) == false)
    #expect(try f.store.entities.summaries(type: .person).map(\.entity.id).contains(maya.id))
}

@Test func summariesReadInAFixedNumberOfStatements() throws {
    var f = try Fixture()
    let counter = StatementCounter()
    try f.db.writer.write { db in db.trace { _ in counter.add() } }
    let shared = try f.memory("A", year: 2001)

    func addPeople(_ names: [String]) throws {
        for name in names {
            let person = try f.person(name)
            try f.link(shared, person, roleText: "my \(name.lowercased())")
        }
    }
    func statementsForOneRead() throws -> Int {
        let before = counter.count
        _ = try f.store.entities.summaries(type: .person)
        return counter.count - before
    }

    try addPeople(["Ines", "Tomas"])
    let statementsFor2 = try statementsForOneRead()
    try addPeople((1...18).map { "Person\($0)" })
    let statementsFor20 = try statementsForOneRead()
    #expect(statementsFor2 > 0)
    #expect(statementsFor20 == statementsFor2)
}

@Test func aDetailLinkOnAMomentIsASharedMoment() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), sam = try f.person("Sam")
    for title in ["A", "B"] {
        let event = try f.memory(title)
        try f.link(event, maya)
        try f.link(event, sam, relation: .detail)
    }
    #expect(try f.store.entities.coOccurrences(of: maya.id).map { "\($0.entity.title) \($0.sharedMoments)" } == ["Sam 2"])
}

@Test func factsLinkingBothAreNotSharedMoments() throws {
    var f = try Fixture()
    let maya = try f.person("Maya"), sam = try f.person("Sam")
    for title in ["A", "B"] {
        let fact = try f.memory(title, kind: .fact)
        try f.link(fact, maya, sam)
        try f.link(fact, maya, sam, relation: .detail)
    }
    #expect(try f.store.entities.coOccurrences(of: maya.id).isEmpty)
}

// Final review: only told, visible memories give a tile its words.

@Test func aHiddenOrUntoldMemoryNeverGivesOwnWords() throws {
    var f = try Fixture()
    let sam = try f.person("Sam"), ines = try f.person("Ines")
    // Said twice, but hidden: without the rule it would win on count.
    try f.link(try f.memory("A", hidden: true), sam, roleText: "my secret friend")
    try f.link(try f.memory("A2", hidden: true), sam, roleText: "my secret friend")
    try f.link(try f.memory("B"), sam, roleText: "my neighbour")
    try f.link(try f.floating("C"), ines, roleText: "the woman next door")
    #expect(try f.store.entities.ownWords(of: sam.id) == "my neighbour", "a hidden memory's words never label a tile")
    #expect(try f.store.entities.ownWords(of: ines.id) == nil, "a floating stand-in is not told")
}

@Test func anAliasIsTrimmedLikeARoleText() {
    #expect(OwnWords.choose(title: "Maya", aliases: ["  my sister "], roleTexts: []) == "my sister")
}
