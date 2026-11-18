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

/// A date the person said or confirmed is theirs. "Use this date" replaces the range and its evidence text with no undo,
/// so the card must not offer it there, however far the photo's day is from the band.
@Test func offersDateNeverReplacesADateThePersonSaid() {
    let photoDay = day(2019, 7, 14)
    for origin in [RangeOrigin.stated, .confirmed] {
        let said = TimeRange(earliest: day(2012, 1, 1), latest: day(2012, 12, 31), likelyStart: nil, likelyEnd: nil,
                             granularity: .year, origin: origin, evidenceText: "in 2012")
        #expect(!PhotoStory.offersDate(photoDay, for: said), "\(origin)")
        // Said words with no dates yet ("when I was little") are still the person's words.
        var saidUnplaced = TimeRange.unplaced
        saidUnplaced.origin = origin
        saidUnplaced.evidenceText = "when I was little"
        #expect(!PhotoStory.offersDate(photoDay, for: saidUnplaced), "\(origin), unplaced")
    }
    // A guess outside the band still gets the offer.
    for origin in [RangeOrigin.inferred, .derived] {
        let guess = TimeRange(earliest: day(2012, 1, 1), latest: day(2012, 12, 31), likelyStart: nil, likelyEnd: nil,
                              granularity: .year, origin: origin, evidenceText: nil)
        #expect(PhotoStory.offersDate(photoDay, for: guess), "\(origin)")
    }
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

@Test func theCardNamesTheOwnersPage() {
    let m = memory("The tree house"), me = entity("Jo"), amy = entity("Amy")
    #expect(card(memories: [m], linked: [m.id: [me, amy]], owner: me.id).ownerEntity == me.id)
    #expect(card(memories: [m], linked: [m.id: [me, amy]]).ownerEntity == nil)
}

// MARK: - The delete dialog's sentence

@Test func theDeleteSentence() {
    let m = memory("The tree house")
    func card(otherHome: Bool) -> PhotoStoryCard {
        PhotoStory.card(photo: photo(), sessionMemories: [m], holding: [m.id], linked: [:], pagesWithPhoto: [], ownerEntity: nil,
                        hasPendingMoments: false, hasOtherHome: otherHome)
    }
    #expect(PhotoStory.deleteSentence(card: nil) == nil, "an ordinary session says nothing")
    #expect(PhotoStory.deleteSentence(card: card(otherHome: true)) == nil, "the photo stays: a page or another story holds it")
    #expect(PhotoStory.deleteSentence(card: card(otherHome: false)) == "Its photo goes too.")
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

    func pendingCard(title: String = "The tree house", ordinal: Int = 0, words: (Int, Int) = (0, 1)) throws -> Candidate {
        let out = MemoryOut(ref: "m1", title: title, quote: "the tree", segmentSpan: WordSpan(startWord: words.0, endWord: words.1),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let card = StoreFixtures.candidate(segments[0].id, ordinal: ordinal, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(card)
        return card
    }

    /// A kept memory first told in another, earlier session.
    func olderMemory(_ title: String) throws -> Memory {
        let (_, older) = try StoreFixtures.session(in: store.sessions, segments: ["the old house"])
        return try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: older[0].id, title: title,
                                        createdAt: .now.addingTimeInterval(-3600))
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

@Test func theCardListsAMemoryATellingWasMergedInto() throws {
    let f = try StoryFixture()
    // An older memory, first told in another session: its order-0 span is not in the photo session.
    let target = try f.olderMemory("The old house")
    let dad = try f.store.entities.insert(type: .person, title: "Dad")
    try f.store.entities.link(target.id, dad.id, relation: .mention)
    _ = try CandidateActions(store: f.store).mergeCandidate(try f.pendingCard(), into: target.id)
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(card.memories.map(\.id) == [target.id], "the memory the telling went into holds the photo, so the card lists it")
    #expect(card.memories.map(\.title) == ["The old house"])
    #expect(card.pageOffers.map(\.id) == [dad.id], "the merged-into memory's pages are offered")
    #expect(card.dateOffers.map(\.id) == [target.id], "the merged-into memory is unplaced, so its date is offered")
}

@Test func theCardListsEachMemoryOnceInTheOrderThisSessionToldIt() throws {
    let f = try StoryFixture()
    let target = try f.olderMemory("The old house")
    let actions = CandidateActions(store: f.store)
    let kept = try actions.acceptMemory(try f.pendingCard()).memory
    // Two later tellings of the older memory, both after the kept one in this session.
    _ = try actions.mergeCandidate(try f.pendingCard(title: "The old house", ordinal: 1, words: (1, 1)), into: target.id)
    _ = try actions.mergeCandidate(try f.pendingCard(title: "The old house", ordinal: 2, words: (2, 2)), into: target.id)
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(card.memories.map(\.id) == [kept.id, target.id], "each memory once, by its first telling in this session")
}

@Test func theReaderOffersTheNamedPagesAndTheDateAndAppliesTaps() throws {
    let f = try StoryFixture()
    let kept = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard()).memory
    let maya = try f.store.entities.insert(type: .person, title: "Maya")
    try f.store.entities.link(kept.id, maya.id, relation: .mention)
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(card.pageOffers.map(\.id) == [maya.id])
    try f.reader.addToPage(f.subject.id, maya.id)
    let offer = try #require(card.dateOffers.first)
    try f.reader.useDate(offer.date, for: [offer.memory])
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
    try f.reader.useDate(day(2019, 7, 14), for: [kept])
    #expect(try f.store.chapters.chapter(id: chapter.id)?.range.earliest == day(2019, 7, 14))
}

/// The card was drawn, then the date changed elsewhere (the person set it, or the resolver placed it). The offer is stale:
/// the tap must not replace a range the person never saw the offer against.
@Test func usingTheDateSkipsAMemoryWhoseRangeChangedSinceTheCard() throws {
    let f = try StoryFixture()
    let kept = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard()).memory
    let said = TimeRange.year(2012, origin: .stated, evidence: "in 2012")
    try f.store.memories.updateRange(kept.id, said)
    let changes = try f.reader.useDate(day(2019, 7, 14), for: [kept])
    #expect(try f.store.memories.fetch(kept.id)?.range == said)
    #expect(changes.isEmpty)
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
    try f.reader.useDate(day(2019, 7, 14), for: [beach])
    #expect(try f.store.memories.fetch(beach.id)?.range == .fromPhoto(day(2019, 7, 14)), "the photo-dated memory does not move")
    let placed = try #require(try f.store.memories.fetch(picnic.id)?.range)
    #expect(placed.isPlaced && placed.earliest.map { $0 >= day(2019, 7, 14) } == true, "the memory that points at it is placed after it")
}

/// "The `photo` origin through a date change" (spec, Tests): the person's own date replaces the photo's in the store.
@Test func aStatedDateReplacesAPhotoDate() throws {
    let f = try StoryFixture()
    let actions = CandidateActions(store: f.store)
    let kept = try actions.acceptMemory(try f.pendingCard()).memory
    try f.reader.useDate(day(2019, 7, 14), for: [kept])
    #expect(try f.store.memories.fetch(kept.id)?.range.origin == .photo)
    try actions.setStatedRange(kept.id, .stated(year: 2018))
    let after = try #require(try f.store.memories.fetch(kept.id)?.range)
    #expect(after.origin == .stated && !after.isFromPhoto)
    #expect(after == .stated(year: 2018))
}

// MARK: - Several ranges in one write, and Undo

private let d = day(2019, 7, 14)

/// Two kept memories, both unplaced, and a chapter "Summers" that holds the first.
private struct TwoMemories {
    let f: StoryFixture
    let a: Memory, b: Memory
    let chapter: Chapter
    init() throws {
        f = try StoryFixture()
        let actions = CandidateActions(store: f.store)
        let first = try actions.acceptMemory(try f.pendingCard(ordinal: 0)).memory
        let second = try actions.acceptMemory(try f.pendingCard(title: "The beach", ordinal: 1)).memory
        chapter = try actions.createChapter(title: "Summers", containing: first.id)
        // Read from the store, as the card does.
        a = try #require(try f.store.memories.fetch(first.id))
        b = try #require(try f.store.memories.fetch(second.id))
    }
    func range(_ m: Memory) throws -> TimeRange { try #require(try f.store.memories.fetch(m.id)).range }
    func chapterEarliest() throws -> CivilDate? { try f.store.chapters.chapter(id: chapter.id)?.range.earliest }
}

@Test func updateRangesChangesSeveralMemoriesInOneWrite() throws {
    let t = try TwoMemories()
    let counter = WriteCounter()
    try t.f.db.writer.write { db in db.trace { counter.note($0.expandedDescription) } }
    let changed = try t.f.store.memories.updateRanges([.init(memory: t.a.id, range: .fromPhoto(d), ifCurrently: t.a.range),
                                                       .init(memory: t.b.id, range: .fromPhoto(d), ifCurrently: t.b.range)])
    #expect(changed == [t.a.id, t.b.id])
    #expect(counter.count == 1)
    #expect(try t.range(t.a) == .fromPhoto(d) && t.range(t.b) == .fromPhoto(d))
    #expect(try t.chapterEarliest() == d)
}

@Test func updateRangesSkipsAMemoryWhoseRangeChanged() throws {
    let t = try TwoMemories()
    let changes: [MemoryRepository.RangeChange] = [.init(memory: t.a.id, range: .fromPhoto(d), ifCurrently: t.a.range),
                                                   .init(memory: t.b.id, range: .fromPhoto(d), ifCurrently: t.b.range)]
    let said = TimeRange.year(2012, origin: .stated, evidence: "in 2012")
    try t.f.store.memories.updateRange(t.b.id, said)
    #expect(try t.f.store.memories.updateRanges(changes) == [t.a.id])
    #expect(try t.range(t.b) == said)
}

@Test func updateRangesSkipsAMemoryThatIsGone() throws {
    let t = try TwoMemories()
    let changes: [MemoryRepository.RangeChange] = [.init(memory: t.a.id, range: .fromPhoto(d), ifCurrently: t.a.range),
                                                   .init(memory: t.b.id, range: .fromPhoto(d), ifCurrently: t.b.range)]
    try t.f.db.writer.write { db in _ = try Memory.deleteOne(db, key: t.b.id.rawValue) }
    #expect(try t.f.store.memories.updateRanges(changes) == [t.a.id])
}

@Test func updateRangesWithNothingWritesNothing() throws {
    let t = try TwoMemories()
    let counter = WriteCounter()
    try t.f.db.writer.write { db in db.trace { counter.note($0.expandedDescription) } }
    #expect(try t.f.store.memories.updateRanges([]) == [])
    #expect(counter.count == 0)
}

@Test func useDateReturnsTheOldRangeOfEachMemoryItChanged() throws {
    let t = try TwoMemories()
    let staleB = t.b
    try t.f.store.memories.updateRange(t.b.id, .year(2012, origin: .stated, evidence: "in 2012"))
    #expect(try t.f.reader.useDate(d, for: [t.a, staleB]) == [PhotoDateChange(memory: t.a.id, before: .unplaced, date: d)])
}

@Test func undoDatePutsBackEachRange() throws {
    let t = try TwoMemories()
    let changes = try t.f.reader.useDate(d, for: [t.a, t.b])
    #expect(try t.f.reader.undoDate(changes) == [t.a.id, t.b.id])
    #expect(try t.range(t.a) == .unplaced && t.range(t.b) == .unplaced)
}

@Test func undoDateSkipsAMemoryThatChangedAfterTheTap() throws {
    let t = try TwoMemories()
    let changes = try t.f.reader.useDate(d, for: [t.a, t.b])
    try CandidateActions(store: t.f.store).setStatedRange(t.a.id, .stated(year: 2018))
    #expect(try t.f.reader.undoDate(changes) == [t.b.id])
    #expect(try t.range(t.a) == .stated(year: 2018))
    #expect(try t.range(t.b) == .unplaced)
}

@Test func undoDateStillWorksAfterThePhotoLeftTheMemory() throws {
    let t = try TwoMemories()
    let changes = try t.f.reader.useDate(d, for: [t.a])
    _ = try t.f.store.photos.unlink(t.f.subject.id, from: .memory(t.a.id))
    #expect(try t.f.reader.undoDate(changes) == [t.a.id])
    #expect(try t.range(t.a) == .unplaced)
}

@Test func undoDateMovesTheChapterBack() throws {
    let t = try TwoMemories()
    let changes = try t.f.reader.useDate(d, for: [t.a])
    #expect(try t.chapterEarliest() == d)
    try t.f.reader.undoDate(changes)
    #expect(try t.chapterEarliest() == nil)
}
