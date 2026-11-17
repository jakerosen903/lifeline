import Foundation
import Testing
@testable import LifelineKit

private func day(_ y: Int, _ m: Int, _ d: Int) -> CivilDate { CivilDate(year: y, month: m, day: d)! }
private func range(_ a: CivilDate?, _ b: CivilDate?) -> TimeRange {
    TimeRange(earliest: a, latest: b, likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: nil)
}

// MARK: - offersDate

@Test func offersDate() {
    let photoDay = day(2019, 7, 14)
    // Unplaced: the photo can place it.
    #expect(PhotoStory.offersDate(photoDay, for: .unplaced))
    // Inside the band: the date does not contradict the memory, so nothing is offered.
    #expect(!PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), day(2019, 12, 31))))
    // One day outside either edge.
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 7, 15), day(2019, 12, 31))))
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), day(2019, 7, 13))))
    // On an edge.
    #expect(!PhotoStory.offersDate(photoDay, for: range(day(2019, 7, 14), day(2019, 12, 31))))
    #expect(!PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), day(2019, 7, 14))))
    // No date on the photo.
    #expect(!PhotoStory.offersDate(nil, for: .unplaced))
    #expect(!PhotoStory.offersDate(nil, for: range(day(2019, 1, 1), day(2019, 12, 31))))
    // Already that day, from the photo.
    #expect(!PhotoStory.offersDate(photoDay, for: .fromPhoto(photoDay)))
    // Half-open: a missing edge is unbounded.
    #expect(!PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), nil)))
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2020, 1, 1), nil)))
    #expect(!PhotoStory.offersDate(photoDay, for: range(nil, day(2020, 1, 1))))
    #expect(PhotoStory.offersDate(photoDay, for: range(nil, day(2018, 1, 1))))
}

// MARK: - card

private func photo(taken: CivilDate? = day(2019, 7, 14)) -> Photo {
    Photo(fileName: "p.jpg", takenAt: taken.flatMap { PhotoTakenAt(stored: String(format: "%04d-%02d-%02dT12:00:00", $0.year, $0.month, $0.day)) },
          sha256: "hash-p", pixelWidth: 400, pixelHeight: 300, addedAt: .now)
}
private func memory(_ title: String, range: TimeRange = .unplaced) -> Memory {
    var m = Memory(id: .init(), title: title, summaryQuote: title, visibility: .timeline, chapterID: nil, createdFromCandidateID: .init(), createdAt: .now)
    m.range = range
    return m
}
private func entity(_ title: String, type: EntityType = .person, hidden: Bool = false, excluded: Bool = false) -> Entity {
    Entity(type: type, title: title, hiddenFromTimeline: hidden, excludedFromAI: excluded)
}
private func card(_ photo: Photo = photo(), memories: [Memory], holding: Set<MemoryID>? = nil, linked: [MemoryID: [Entity]] = [:],
                  pagesWithPhoto: Set<EntityID> = [], owner: EntityID? = nil) -> PhotoStoryCard {
    PhotoStory.card(photo: photo, sessionMemories: memories, holding: holding ?? Set(memories.map(\.id)), linked: linked,
                    pagesWithPhoto: pagesWithPhoto, ownerEntity: owner, hasPendingMoments: false, hasOtherHome: false)
}

@Test func theCardListsWhatHoldsThePhoto() {
    let a = memory("A"), b = memory("B"), c = memory("C")
    let result = card(memories: [a, b, c], holding: [c.id, a.id])
    #expect(result.memories.map(\.id) == [a.id, c.id], "only the memories that hold it, in the order given")
}

@Test func aPageThatHoldsThePhotoIsNotOffered() {
    let m = memory("The tree house"), maya = entity("Maya"), dad = entity("Dad")
    let result = card(memories: [m], linked: [m.id: [maya, dad]], pagesWithPhoto: [maya.id])
    #expect(result.pageOffers.map(\.id) == [dad.id])
}

@Test func aPageIsOfferedOnceWhenTwoMemoriesNameIt() {
    let a = memory("A"), b = memory("B"), maya = entity("Maya"), house = entity("Tree house", type: .thing)
    let result = card(memories: [a, b], linked: [a.id: [maya, house], b.id: [maya]])
    #expect(result.pageOffers.count == 2)
    #expect(Set(result.pageOffers.map(\.id)) == [maya.id, house.id], "every entity type is offered")
}

@Test func theOwnersPageLeadsTheOffers() {
    let m = memory("The tree house"), me = entity("Jo"), amy = entity("Amy"), zed = entity("Zed")
    let result = card(memories: [m], linked: [m.id: [zed, amy, me]], owner: me.id)
    #expect(result.pageOffers.map(\.title) == ["Jo", "Amy", "Zed"])
}

@Test func aHiddenPageIsNotOffered() {
    let m = memory("The tree house"), hidden = entity("Hidden", hidden: true), kept = entity("Private", excluded: true)
    let result = card(memories: [m], linked: [m.id: [hidden, kept]])
    #expect(result.pageOffers.map(\.id) == [kept.id], "hidden from browsing blocks an offer; kept from the AI does not")
}

@Test func aMemoryWithoutThePhotoGetsNoDateOffer() {
    let holds = memory("Holds"), doesNot = memory("Does not")
    let result = card(memories: [holds, doesNot], holding: [holds.id])
    #expect(result.dateOffers.map(\.id) == [holds.id])
    #expect(result.dateOffers.first?.date == day(2019, 7, 14))
}

@Test func aPhotoWithNoDateOffersNoDate() {
    let m = memory("The tree house")
    #expect(card(photo(taken: nil), memories: [m]).dateOffers.isEmpty)
}

// MARK: - The reader

private struct StoryFixture {
    let db: AppDatabase
    let store: ExtractionStore
    let sessionID: SessionID
    let segments: [Segment]
    let subject: Photo

    init(photoSession: Bool = true) throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        (sessionID, segments) = try StoreFixtures.session(in: store.sessions, segments: ["the tree house"])
        subject = Photo(fileName: "story.jpg", takenAt: PhotoTakenAt(stored: "2019-07-14T09:30:00"),
                        sha256: "hash-story", pixelWidth: 400, pixelHeight: 300, addedAt: .now)
        if photoSession {
            try store.photos.insert(subject)
            var row = try #require(try store.sessions.fetch(sessionID))
            row.subjectPhotoID = subject.id; row.startedFrom = .photo
            try store.sessions.update(row)
        }
    }

    var reader: PhotoStoryReader { PhotoStoryReader(store: store) }

    func pendingCard(title: String = "The tree house") throws -> Candidate {
        let out = MemoryOut(ref: "m1", title: title, quote: "the tree", segmentSpan: WordSpan(startWord: 0, endWord: 1),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let card = StoreFixtures.candidate(segments[0].id, ordinal: 0, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(card)
        return card
    }
}

@Test func theReaderGivesNoCardForAnOrdinarySession() throws {
    let f = try StoryFixture(photoSession: false)
    #expect(try f.reader.card(for: f.sessionID) == nil)
}

@Test func theReaderSeesAMemoryKeptLater() throws {
    let f = try StoryFixture()
    let pending = try f.pendingCard()
    let before = try #require(try f.reader.card(for: f.sessionID))
    #expect(before.memories.isEmpty && before.hasPendingMoments)
    #expect(before.photo.id == f.subject.id)
    try f.store.sessions.setStatus(.extracted, for: f.segments[0].id)
    let kept = try CandidateActions(store: f.store).acceptMemory(pending).memory
    let after = try #require(try f.reader.card(for: f.sessionID))
    #expect(after.memories.map(\.id) == [kept.id])
    #expect(!after.hasPendingMoments)
    #expect(after.dateOffers.map(\.id) == [kept.id], "the kept memory is unplaced, so the photo's date is offered")
    #expect(!after.hasOtherHome)
}

@Test func theReaderOffersTheNamedPagesAndTheDateAndAppliesTaps() throws {
    let f = try StoryFixture()
    let kept = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard()).memory
    let maya = try f.store.entities.insert(type: .person, title: "Maya")
    try f.store.entities.link(kept.id, maya.id, relation: .mention)
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(card.pageOffers.map(\.id) == [maya.id])
    try f.reader.addToPage(f.subject.id, maya.id)
    try f.reader.useDate(try #require(card.dateOffers.first))
    let after = try #require(try f.reader.card(for: f.sessionID))
    #expect(after.pageOffers.isEmpty && after.dateOffers.isEmpty)
    #expect(try f.store.memories.fetch(kept.id)?.range == .fromPhoto(day(2019, 7, 14)))
    #expect(after.hasOtherHome)
}

@Test func addToPageUsesTheCoverRule() throws {
    let f = try StoryFixture()
    let dad = try f.store.entities.insert(type: .person, title: "Dad"), maya = try f.store.entities.insert(type: .person, title: "Maya")
    let other = Photo(fileName: "o.jpg", sha256: "hash-o", pixelWidth: 400, pixelHeight: 300, addedAt: .now)
    try f.store.photos.insert(other, linkingTo: .entity(maya.id))
    try f.reader.addToPage(f.subject.id, dad.id)
    try f.reader.addToPage(f.subject.id, maya.id)
    #expect(try f.store.photos.photos(of: .entity(dad.id)).map(\.role) == [.cover])
    #expect(try f.store.photos.photos(of: .entity(maya.id)).map(\.role) == [.cover, .attached])
}

@Test func usingTheDateMovesTheMemorysChapterWithIt() throws {
    let f = try StoryFixture()
    let kept = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard()).memory
    let chapter = try CandidateActions(store: f.store).createChapter(title: "Summers", containing: kept.id)
    try f.reader.useDate(PhotoStoryCard.DateOffer(memory: kept, date: day(2019, 7, 14)))
    #expect(try f.store.chapters.chapter(id: chapter.id)?.range.earliest == day(2019, 7, 14))
}

private final class WriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func note(_ sql: String) { if sql.uppercased().hasPrefix("BEGIN IMMEDIATE") { lock.withLock { value += 1 } } }
    var count: Int { lock.withLock { value } }
}

@Test func usingTheDateIsOneWrite() throws {
    let f = try StoryFixture()
    let kept = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard()).memory
    let chapter = try CandidateActions(store: f.store).createChapter(title: "Summers", containing: kept.id)
    let counter = WriteCounter()
    try f.db.writer.write { db in db.trace { counter.note($0.expandedDescription) } }
    try f.store.memories.updateRange(kept.id, .fromPhoto(day(2019, 7, 14)), refreshingChapter: true)
    #expect(counter.count == 1, "the memory and its chapter change in one transaction")
    #expect(try f.store.chapters.chapter(id: chapter.id)?.range.earliest == day(2019, 7, 14))
}

@Test func usingTheDateRePlacesAMemoryThatPointsAtIt() throws {
    let f = try StoryFixture()
    let actions = CandidateActions(store: f.store)
    let beach = try actions.acceptMemory(try f.pendingCard(title: "The beach")).memory
    let out = MemoryOut(ref: "m2", kind: .event, title: "The picnic", quote: "the tree", segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [],
                        placeText: nil, anchors: [AnchorOut(phrase: "after The beach", relation: .after, targetText: "The beach", value: nil)],
                        collectionHint: nil, chapterHint: nil, confidence: 0.9)
    let c = StoreFixtures.candidate(f.segments[0].id, ordinal: 1, payload: try CandidatePayload.encode(out))
    try f.store.candidates.insert(c)
    let picnic = try actions.acceptMemory(c).memory
    try f.store.memories.updateRange(beach.id, .unplaced)
    #expect(try f.store.memories.fetch(picnic.id)?.range.isPlaced == false)
    try f.reader.useDate(PhotoStoryCard.DateOffer(memory: beach, date: day(2019, 7, 14)))
    #expect(try f.store.memories.fetch(beach.id)?.range == .fromPhoto(day(2019, 7, 14)), "the photo-dated memory does not move")
    let placed = try #require(try f.store.memories.fetch(picnic.id)?.range)
    #expect(placed.isPlaced && placed.earliest.map { $0 >= day(2019, 7, 14) } == true, "the memory that points at it is placed after it")
}
