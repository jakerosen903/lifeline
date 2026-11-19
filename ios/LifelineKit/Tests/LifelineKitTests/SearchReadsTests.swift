import Foundation
import Testing
@testable import LifelineKit

/// Counts the statements one connection runs.
private final class StatementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// An archive with an owner (Jordan), one recording, and "The long drive" told over the words "he kept an old harmonica in the glove box".
private struct Fixture {
    static let said = "um so anyway he kept an old harmonica in the glove box"

    let db: AppDatabase
    let store: ExtractionStore
    let sessionID: SessionID
    let segment: Segment
    let drive: Memory
    let maya: Person

    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        try store.profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        let (session, segments) = try StoreFixtures.session(in: store.sessions, segments: [Self.said])
        sessionID = session
        segment = segments[0]
        drive = try Self.tell("The long drive", words: 3...11, in: segment, store: store)
        maya = try store.people.insertPerson(displayName: "Maya")
        try store.people.addAlias("May", to: maya.id)
    }

    /// A kept memory, from a card of its own, whose span covers these words of the segment.
    @discardableResult
    static func tell(_ title: String, words: ClosedRange<Int>, in segment: Segment, ordinal: Int = 0, store: ExtractionStore) throws -> Memory {
        let rows = try store.sessions.words(in: segment.id)
        let candidate = StoreFixtures.candidate(segment.id, ordinal: ordinal)
        try store.candidates.insert(candidate)
        var memory = StoreFixtures.memory(from: candidate.id, title: title)
        memory.summaryQuote = title
        try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: rows[words.lowerBound].startMs,
                                                              endMs: rows[words.upperBound].endMs, order: 0)],
                                  people: [], places: [], anchors: [], acceptingCandidate: candidate.id)
        return memory
    }

    func tell(_ title: String, words: ClosedRange<Int>, in segment: Segment, ordinal: Int = 0) throws -> Memory {
        try Self.tell(title, words: words, in: segment, ordinal: ordinal, store: store)
    }

    func titles(_ type: EntityType, in index: SearchIndex) -> [String] {
        index.entities.filter { $0.summary.entity.type == type }.map(\.summary.entity.title)
    }
}

@Test func theIndexHoldsWhatTheAppShows() throws {
    let f = try Fixture()
    _ = try f.store.entities.insert(type: .place, title: "Alder Street")
    _ = try f.store.entities.insert(type: .thing, title: "Dad's Volvo")
    _ = try f.store.entities.insert(type: .idea, title: "Saying yes to things")
    let index = try f.store.searchIndex()
    #expect(Set(index.entities.map(\.summary.entity.title)) == ["Maya", "Alder Street", "Dad's Volvo", "Saying yes to things"])
    #expect(index.entities.first { $0.summary.entity.title == "Maya" }?.aliases == ["May"], "the alias equal to the name is dropped")
    #expect(index.memories.map(\.memory.title) == ["The long drive"])
    #expect(index.memories.first?.tellings == ["he kept an old harmonica in the glove box"])
    let session = try #require(try f.store.sessions.fetch(f.sessionID))
    #expect(index.memories.first?.toldAt == session.startedAt)
}

@Test func aHiddenMemoryIsNotInTheIndex() throws {
    let f = try Fixture()
    try f.store.memories.setHidden(f.drive.id, true)
    #expect(try f.store.searchIndex().memories.isEmpty)
    #expect(Search.run("harmonica", in: try f.store.searchIndex())?.isEmpty == true)
}

@Test func aHiddenEntityIsNotInTheIndex() throws {
    let f = try Fixture()
    try f.store.entities.setHidden(f.maya.entityID, true)
    #expect(try f.store.searchIndex().entities.contains { $0.summary.entity.id == f.maya.entityID } == false)
}

@Test func aMemoryAndAnEntityKeptFromAIAreInTheIndex() throws {
    let f = try Fixture()
    try f.store.memories.setExcluded(f.drive.id, true)
    try f.store.entities.setExcluded(f.maya.entityID, true)
    let index = try f.store.searchIndex()
    #expect(index.memories.count == 1 && index.entities.contains { $0.summary.entity.id == f.maya.entityID }, "decision 6")
}

@Test func aStandInAndTheOwnerAreNotInTheIndex() throws {
    let f = try Fixture()
    let standIn = try f.store.memories.insertFloating(title: "Graduation", segment: f.segment.id, startMs: 0, endMs: 500)
    let index = try f.store.searchIndex()
    #expect(index.memories.map(\.memory.title) == ["The long drive"])
    #expect(index.memories.contains { $0.memory.id == standIn.id } == false)
    #expect(index.entities.contains { $0.summary.entity.title == "Jordan" } == false)
    #expect(Search.run("graduation", in: index)?.isEmpty == true)
}

@Test func wordsOutsideTheSpanAreNotInTheIndex() throws {
    let f = try Fixture()
    #expect(try f.store.searchIndex().memories.first?.tellings == ["he kept an old harmonica in the glove box"])
    // Trim the telling to "he kept an old harmonica": the later words leave the index.
    let actions = CandidateActions(store: f.store)
    _ = try actions.trimTelling(f.drive.id, order: 0, startWord: 3, endWord: 7)
    let index = try f.store.searchIndex()
    #expect(index.memories.first?.tellings == ["he kept an old harmonica"])
    #expect(Search.run("glove", in: index)?.isEmpty == true)
}

@Test func aSegmentWithNoKeptMemoryIsNotInTheIndex() throws {
    let f = try Fixture()
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["the accordion in the attic"])
    try f.store.candidates.insert(StoreFixtures.candidate(segments[0].id))
    // A stand-in's span covers "accordion", but a stand-in was never kept: its words are not read.
    let rows = try f.store.sessions.words(in: segments[0].id)
    let standIn = try f.store.memories.insertFloating(title: "Attic", segment: segments[0].id, startMs: rows[0].startMs, endMs: rows[4].endMs)
    #expect(try f.store.memories.tellingWords()[standIn.id] == nil)
    #expect(Search.run("accordion", in: try f.store.searchIndex())?.isEmpty == true, "decision 18")
}

@Test func twoKeptMemoriesOnDisjointSpansOfOneSegmentKeepTheirOwnWords() throws {
    let f = try Fixture()
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["we dug a canal behind the shed then we flew a red kite"])
    let canal = try f.tell("The canal", words: 0...6, in: segments[0])
    let kite = try f.tell("The kite", words: 7...12, in: segments[0], ordinal: 1)
    let index = try f.store.searchIndex()
    #expect(index.memories.first { $0.memory.id == canal.id }?.tellings == ["we dug a canal behind the shed"])
    #expect(index.memories.first { $0.memory.id == kite.id }?.tellings == ["then we flew a red kite"])
}

@Test func aSpanWithNoWordRowsAddsNothing() throws {
    let f = try Fixture()
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: [""])
    let candidate = StoreFixtures.candidate(segments[0].id)
    try f.store.candidates.insert(candidate)
    let treeHouse = StoreFixtures.memory(from: candidate.id, title: "The tree house")
    try f.store.memories.insert(treeHouse, spans: [MemorySpan(memoryID: treeHouse.id, segmentID: segments[0].id, startMs: 0, endMs: 1000, order: 0)],
                                people: [], places: [], anchors: [], acceptingCandidate: candidate.id)
    let index = try f.store.searchIndex()
    #expect(index.memories.first { $0.memory.title == "The tree house" }?.tellings == [])
    #expect(Search.run("tree", in: index)?.memories.count == 1, "the title still finds it")
}

@Test func aRetellingIsASecondTelling() throws {
    let f = try Fixture()
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["the harmonica again in the glove box"])
    let rows = try f.store.sessions.words(in: segments[0].id)
    let candidate = StoreFixtures.candidate(segments[0].id)
    try f.store.candidates.insert(candidate)
    let span = MemorySpan(memoryID: f.drive.id, segmentID: segments[0].id, startMs: rows[1].startMs, endMs: rows[1].endMs, order: 1, candidateID: candidate.id)
    try f.store.memories.mergeSpan(span, people: [], places: [], anchors: [], promotingStandIn: nil, acceptingCandidate: candidate.id)
    let entry = try #require(try f.store.searchIndex().memories.first)
    #expect(entry.tellings == ["he kept an old harmonica in the glove box", "harmonica"], "first telling first")
}

@Test func aContinuationSpanIsItsOwnEntry() throws {
    let f = try Fixture()
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["and then we sang along"])
    let rows = try f.store.sessions.words(in: segments[0].id)
    let candidate = StoreFixtures.candidate(segments[0].id)
    try f.store.candidates.insert(candidate)
    let span = MemorySpan(memoryID: f.drive.id, segmentID: segments[0].id, startMs: rows[0].startMs, endMs: rows[0].endMs, order: 1,
                          candidateID: candidate.id, continuesOrder: 0)
    try f.store.memories.insertSpan(span)
    #expect(try f.store.searchIndex().memories.first?.tellings == ["he kept an old harmonica in the glove box", "and"])
}

@Test func aMergedEntityIsOneEntry() throws {
    let f = try Fixture()
    // `insert` reuses a title, so the twins are written together, as extraction writes them.
    let ohio = Entity(type: .place, title: "Ohio"), ohioDot = Entity(type: .place, title: "Ohio.")
    var write = EntityRepository.Write()
    write.entities = [ohio, ohioDot]
    try f.store.entities.apply(write)
    #expect(f.titles(.place, in: try f.store.searchIndex()).count == 2)
    #expect(try f.store.entities.merge(ohioDot.id, into: ohio.id))
    #expect(f.titles(.place, in: try f.store.searchIndex()) == ["Ohio"])
}

@Test func aDeletedMemoryAndADeletedSessionLeaveTheIndex() throws {
    let f = try Fixture()
    try f.store.memories.delete(f.drive.id)
    #expect(try f.store.searchIndex().memories.isEmpty)

    let (session, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["we dug a canal behind the shed"])
    try f.tell("The canal", words: 0...5, in: segments[0])
    #expect(try f.store.searchIndex().memories.map(\.memory.title) == ["The canal"])
    try f.store.sessions.deleteSession(session)
    let index = try f.store.searchIndex()
    #expect(index.memories.isEmpty)
    #expect(Search.run("canal", in: index)?.isEmpty == true)
}

@Test func aRenamedPersonIsStillFoundByTheOldName() throws {
    let f = try Fixture()
    try f.store.people.rename(f.maya.id, to: "Maya Okafor")
    let aliases = try #require(try f.store.searchIndex().entities.first { $0.summary.entity.id == f.maya.entityID }?.aliases)
    #expect(aliases.contains("Maya"), "the old spelling stays: its fold differs from the title's")
    #expect(aliases.contains("May"))
    #expect(Search.run("maya", in: try f.store.searchIndex())?.people.map(\.id) == [f.maya.entityID])
}

@Test func aHiddenPersonsAliasesAreNotRead() throws {
    let f = try Fixture()
    #expect(try f.store.people.allAliases()[f.maya.entityID]?.contains("May") == true)
    try f.store.entities.setHidden(f.maya.entityID, true)
    #expect(try f.store.people.allAliases()[f.maya.entityID] == nil)
}

@Test func theOwnersAliasesAreNotRead() throws {
    let f = try Fixture()
    let owner = try #require(try f.store.profile.owner())
    try f.store.people.addAlias("Jo", to: owner.id)
    #expect(try f.store.people.allAliases()[owner.entityID] == nil)
}

@Test func aPhotoStoryMemoryIsInTheIndex() throws {
    let f = try Fixture()
    // A memory kept from a photo story has a card like any other; the photo is only a link.
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["this was the lake house in august"])
    let kept = try f.tell("The lake house", words: 0...6, in: segments[0])
    let photo = Photo(fileName: "p.jpg", takenAt: nil, sha256: "hash-lake", pixelWidth: 400, pixelHeight: 300, addedAt: .now)
    try f.store.photos.insert(photo, linkingTo: .memory(kept.id))
    let index = try f.store.searchIndex()
    #expect(index.memories.contains { $0.memory.id == kept.id })
    #expect(index.memories.first { $0.memory.id == kept.id }?.tellings == ["this was the lake house in august"])
}

@Test func anEmptyArchiveGivesAnEmptyIndex() throws {
    #expect(try ExtractionStore(try AppDatabase.inMemory()).searchIndex() == .empty)
}

@Test func theIndexReadsInAFixedNumberOfStatements() throws {
    let f = try Fixture()
    let counter = StatementCounter()
    try f.db.writer.write { db in db.trace { _ in counter.add() } }
    func statementsForOneRead() throws -> Int {
        let before = counter.count
        _ = try f.store.searchIndex()
        return counter.count - before
    }
    let few = try statementsForOneRead()
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: (1...30).map { "we all sat on the porch, time \($0)" })
    for (i, segment) in segments.enumerated() {
        try f.tell("Porch \(i)", words: 0...5, in: segment)
        let person = try f.store.people.insertPerson(displayName: "Guest \(i)")
        try f.store.people.addAlias("G\(i)", to: person.id)
        _ = try f.store.entities.insert(type: .place, title: "Place \(i)")
    }
    let many = try statementsForOneRead()
    #expect(few > 0)
    #expect(many == few)
    #expect(try f.store.searchIndex().memories.count == 31)
}
