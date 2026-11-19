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
    // Inside the band: a guess is still a guess, so the photo can replace it.
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), day(2019, 12, 31))))
    // One day outside either edge.
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 7, 15), day(2019, 12, 31))))
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), day(2019, 7, 13))))
    // On an edge.
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 7, 14), day(2019, 12, 31))))
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), day(2019, 7, 14))))
    // No date on the photo.
    #expect(!PhotoStory.offersDate(nil, for: .unplaced))
    #expect(!PhotoStory.offersDate(nil, for: range(day(2019, 1, 1), day(2019, 12, 31))))
    // Already that day, from the photo.
    #expect(!PhotoStory.offersDate(photoDay, for: .fromPhoto(photoDay)))
    // A date from another photo: the person changes it on the memory's page.
    #expect(!PhotoStory.offersDate(photoDay, for: .fromPhoto(day(2012, 6, 1))))
    // Half-open: a guess with one edge is still a guess.
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2019, 1, 1), nil)))
    #expect(PhotoStory.offersDate(photoDay, for: range(day(2020, 1, 1), nil)))
    #expect(PhotoStory.offersDate(photoDay, for: range(nil, day(2020, 1, 1))))
    #expect(PhotoStory.offersDate(photoDay, for: range(nil, day(2018, 1, 1))))
}

/// A date the person said or confirmed is theirs. "Use this date" replaces the range and its evidence text with no undo,
/// so the card must not offer it there, however far the photo's day is from the band.
@Test func offersDateNeverReplacesADateThePersonSaid() {
    let photoDay = day(2019, 7, 14)
    for origin in [RangeOrigin.stated, .confirmed, .photo] {
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
        // The same guess with the photo day inside its band.
        #expect(PhotoStory.offersDate(day(2012, 6, 14), for: guess), "\(origin), inside")
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
                  pagesWithPhoto: [Entity] = [], owner: EntityID? = nil, pagesDone: Bool = false) -> PhotoStoryCard {
    PhotoStory.card(photo: photo, sessionMemories: memories, holding: holding ?? Set(memories.map(\.id)), linked: linked,
                    pagesWithPhoto: pagesWithPhoto, ownerEntity: owner, hasPendingMoments: false, hasOtherHome: false, pagesDone: pagesDone)
}

@Test func theCardListsWhatHoldsThePhoto() {
    let a = memory("A"), b = memory("B"), c = memory("C")
    let result = card(memories: [a, b, c], holding: [c.id, a.id])
    #expect(result.memories.map(\.id) == [a.id, c.id], "only the memories that hold it, in the order given")
}

@Test func aPageIsOfferedOnceWhenTwoMemoriesNameIt() {
    let a = memory("A"), b = memory("B"), maya = entity("Maya"), house = entity("Tree house", type: .thing)
    let result = card(memories: [a, b], linked: [a.id: [maya, house], b.id: [maya]])
    #expect(pages(result).count == 2)
    #expect(Set(pages(result).map(\.id)) == [maya.id, house.id], "every entity type is offered")
    #expect(result.pageGroups.map(\.type) == [.person, .thing])
}

@Test func aHiddenPageIsNotOffered() {
    let m = memory("The tree house"), hidden = entity("Hidden", hidden: true), kept = entity("Private", excluded: true)
    let result = card(memories: [m], linked: [m.id: [hidden, kept]])
    #expect(pages(result).map(\.id) == [kept.id], "hidden from browsing blocks an offer; kept from the AI does not")
}

@Test func aMemoryWithoutThePhotoGetsNoDateOffer() {
    let holds = memory("Holds"), doesNot = memory("Does not")
    let result = card(memories: [holds, doesNot], holding: [holds.id])
    #expect(result.dateOffer?.memories.map(\.id) == [holds.id])
    #expect(result.dateOffer?.date == day(2019, 7, 14))
}

@Test func aPhotoWithNoDateOffersNoDate() {
    let m = memory("The tree house")
    #expect(card(photo(taken: nil), memories: [m]).dateOffer == nil)
}

@Test func theCardNamesTheOwnersPage() {
    let m = memory("The tree house"), me = entity("Jo"), amy = entity("Amy")
    #expect(pages(card(memories: [m], linked: [m.id: [me, amy]], owner: me.id)).map(\.isOwner) == [true, false])
    #expect(pages(card(memories: [m], linked: [m.id: [me, amy]])).map(\.isOwner) == [false, false])
}

// MARK: - Pages in groups, and the story's date offer

private func pages(_ card: PhotoStoryCard) -> [PhotoStoryCard.Page] { card.pageGroups.flatMap(\.pages) }

@Test func thePagesAreInGroupsInOrder() {
    let m = memory("The picnic")
    let idea = entity("Saying yes", type: .idea), thing = entity("The blue kayak", type: .thing)
    let place = entity("Pelican Beach", type: .place), maya = entity("Maya")
    let result = card(memories: [m], linked: [m.id: [idea, thing, place, maya]])
    #expect(result.pageGroups.map(\.type) == [.person, .place, .thing, .idea])
    #expect(result.pageGroups.map(\.title) == ["People", "Places", "Things", "Ideas"])
}

@Test func aGroupWithNoPageIsLeftOut() {
    let m = memory("The picnic")
    let result = card(memories: [m], linked: [m.id: [entity("The beach", type: .place), entity("Maya")]])
    #expect(result.pageGroups.map(\.type) == [.person, .place])
}

@Test func aPageThatHoldsThePhotoIsChosen() {
    let m = memory("The picnic"), maya = entity("Maya"), dad = entity("Dad")
    let result = card(memories: [m], linked: [m.id: [maya, dad]], pagesWithPhoto: [maya])
    #expect(pages(result).map(\.title) == ["Dad", "Maya"])
    #expect(pages(result).map(\.isChosen) == [false, true])
    #expect(pages(result).map(\.stateValue) == ["not added", "added"])
    #expect(pages(result).first { $0.id == dad.id }?.isChosen == false, "Dad is listed, not chosen")
    #expect(pages(result).first { $0.id == maya.id }?.isChosen == true, "Maya is listed, chosen")
}

@Test func aPageThatHoldsThePhotoAndNoMemoryNamesIsListedChosen() {
    let m = memory("The picnic"), maya = entity("Maya"), dad = entity("Dad")
    let result = card(memories: [m], linked: [m.id: [dad]], pagesWithPhoto: [maya])
    #expect(pages(result).map(\.title) == ["Dad", "Maya"])
    #expect(pages(result).map(\.isChosen) == [false, true])
}

@Test func aHiddenPageThatHoldsThePhotoIsNotListed() {
    let m = memory("The picnic")
    let result = card(memories: [m], pagesWithPhoto: [entity("Hidden", hidden: true)])
    #expect(result.pageGroups.isEmpty)
}

@Test func aPageKeptFromTheAIIsListed() {
    let m = memory("The picnic"), kept = entity("Private", excluded: true)
    let result = card(memories: [m], linked: [m.id: [kept]])
    #expect(pages(result).map(\.id) == [kept.id])
    #expect(pages(result).map(\.isChosen) == [false])
}

@Test func theOwnersChipIsFirstAndReadsYou() {
    let m = memory("The picnic"), zed = entity("Zed"), amy = entity("Amy"), jo = entity("Jo")
    let result = card(memories: [m], linked: [m.id: [zed, amy, jo]], owner: jo.id)
    #expect(pages(result).map(\.title) == ["You", "Amy", "Zed"])
    #expect(pages(result).map(\.isOwner) == [true, false, false])
}

@Test func aPageIsListedOnceWhenTwoMemoriesNameItAndItHoldsThePhoto() {
    let a = memory("A"), b = memory("B"), maya = entity("Maya")
    let result = card(memories: [a, b], linked: [a.id: [maya], b.id: [maya]], pagesWithPhoto: [maya])
    #expect(pages(result).map(\.id) == [maya.id])
    #expect(pages(result).map(\.isChosen) == [true])
}

@Test func twoPagesWithOneTitleAreBothListed() {
    let m = memory("The picnic"), one = entity("Sam"), two = entity("Sam")
    let result = card(memories: [m], linked: [m.id: [two, one]])
    #expect(pages(result).count == 2)
    #expect(pages(result).map(\.id.rawValue) == [one.id.rawValue, two.id.rawValue].sorted())
}

@Test func oneDateOfferForTheStory() {
    let a = memory("A"), c = memory("C", range: range(day(2012, 1, 1), day(2012, 12, 31)))
    let b = memory("B", range: TimeRange(earliest: day(2012, 1, 1), latest: day(2012, 12, 31), likelyStart: nil, likelyEnd: nil,
                                         granularity: .year, origin: .stated, evidenceText: "in 2012"))
    let d = memory("D", range: .fromPhoto(day(2012, 6, 1)))
    let result = card(memories: [a, b, c, d])
    #expect(result.dateOffer == .init(date: day(2019, 7, 14), memories: [a, c]))
}

@Test func noDateOfferWhenNoMemoryCanTakeIt() {
    let b = memory("B", range: TimeRange(earliest: day(2012, 1, 1), latest: day(2012, 12, 31), likelyStart: nil, likelyEnd: nil,
                                         granularity: .year, origin: .stated, evidenceText: "in 2012"))
    let d = memory("D", range: .fromPhoto(day(2012, 6, 1)))
    #expect(card(memories: [b, d]).dateOffer == nil)
}

@Test func noDateOfferWithoutAPhotoDate() {
    #expect(card(photo(taken: nil), memories: [memory("A")]).dateOffer == nil)
}

@Test func aMemoryWithoutThePhotoIsNotInTheDateOffer() {
    let a = memory("A"), c = memory("C", range: range(day(2012, 1, 1), day(2012, 12, 31)))
    let result = card(memories: [a, c], holding: [a.id])
    #expect(result.dateOffer?.memories == [a])
}

@Test func aNonMomentThatHoldsThePhotoIsNotOfferedTheDate() {
    let a = memory("A"), c = memory("C")
    var fact = memory("Dad was a baker"); fact.kind = .fact
    var feeling = memory("I felt free"); feeling.kind = .feeling
    var goal = memory("I want to sail"); goal.kind = .goal
    var other = memory("Something"); other.kind = .other
    let result = card(memories: [a, fact, c, feeling, goal, other])
    #expect(result.dateOffer?.memories == [a, c, other], "only moments take the photo's date: a non-moment's page shows no date")
    let part = PhotoDatePart.state(offer: result.dateOffer, holdingCount: result.memories.count, used: [], seen: [])
    guard case .offer(let offer) = part else { Issue.record("expected an offer"); return }
    #expect(offer.text == "The photo is dated 14 July 2019. Three moments have no date you said.")
    #expect(offer.button == "Use for those 3", "the count leaves out the fact, the feeling and the goal")
}

@Test func onlyNonMomentsLeftHideTheDatePart() {
    var fact = memory("Dad was a baker"); fact.kind = .fact
    var goal = memory("I want to sail"); goal.kind = .goal
    let result = card(memories: [fact, goal])
    #expect(result.dateOffer == nil)
    #expect(PhotoDatePart.state(offer: result.dateOffer, holdingCount: result.memories.count, used: [], seen: []) == .hidden)
}

@Test func theMomentsLine() {
    func result(pending: Bool, kept: Int) -> PhotoStoryCard {
        let memories = (0..<kept).map { memory("M\($0)") }
        return PhotoStory.card(photo: photo(), sessionMemories: memories, holding: Set(memories.map(\.id)), linked: [:], pagesWithPhoto: [],
                               ownerEntity: nil, hasPendingMoments: pending, hasOtherHome: false)
    }
    let waiting = "This photo goes on each moment you keep."
    #expect(result(pending: true, kept: 0).momentsLine == waiting && !result(pending: true, kept: 0).momentsLineOpens)
    #expect(result(pending: true, kept: 1).momentsLine == waiting && !result(pending: true, kept: 1).momentsLineOpens)
    #expect(result(pending: false, kept: 1).momentsLine == "On 1 moment from this story" && result(pending: false, kept: 1).momentsLineOpens)
    #expect(result(pending: false, kept: 5).momentsLine == "On 5 moments from this story" && result(pending: false, kept: 5).momentsLineOpens)
    #expect(result(pending: false, kept: 0).momentsLine == nil && !result(pending: false, kept: 0).momentsLineOpens)
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

    /// `people` are the card's people refs; `place` its place; `aboutSelf` makes it a fact about the owner (a detail link);
    /// `storyRef` joins a story on Keep.
    func pendingCard(title: String = "The tree house", ordinal: Int = 0, words: (Int, Int) = (0, 1), people: [String] = [],
                     place: String? = nil, aboutSelf: Bool = false, storyRef: String? = nil, segment: SegmentID? = nil) throws -> Candidate {
        let out = MemoryOut(ref: "m1", kind: aboutSelf ? .fact : nil, title: title, quote: "the tree",
                            segmentSpan: WordSpan(startWord: words.0, endWord: words.1), peopleRefs: people, placeText: place, anchors: [],
                            storyRef: storyRef, collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: aboutSelf ? "self" : nil)
        let card = StoreFixtures.candidate(segment ?? segments[0].id, ordinal: ordinal, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(card)
        return card
    }

    /// A kept memory first told in another, earlier session.
    func olderMemory(_ title: String) throws -> Memory {
        let (_, older) = try StoreFixtures.session(in: store.sessions, segments: ["the old house"])
        return try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: older[0].id, title: title,
                                        createdAt: .now.addingTimeInterval(-3600))
    }

    /// A person on file, so a card that says the name links to them (`assumed`).
    func person(_ name: String, hidden: Bool = false) throws -> EntityID {
        let id = try store.people.insertPerson(displayName: name).entityID
        if hidden { try store.entities.setHidden(id, true) }
        return id
    }

    func keep(_ card: Candidate) throws -> Memory { try CandidateActions(store: store).acceptMemory(card).memory }

    /// The ids of the photos on an entity's page, in the page's order.
    func page(_ entity: EntityID) throws -> [PhotoID] { try store.photos.photos(of: .entity(entity)).map(\.id) }

    /// The origin of the memory's name link to the entity, as stored.
    func nameLinkOrigin(_ memory: MemoryID, _ entity: EntityID) throws -> String? {
        try db.writer.read { try String.fetchOne($0, sql: "select origin from moment_entity where memory_id = ? and entity_id = ?",
                                                 arguments: [memory.rawValue, entity.rawValue]) }
    }

    func isNamed(_ entity: EntityID, by memory: MemoryID) throws -> Bool {
        try db.writer.read { try Bool.fetchOne($0, sql: "select exists (select 1 from moment_entity where memory_id = ? and entity_id = ?)",
                                               arguments: [memory.rawValue, entity.rawValue]) ?? false }
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
    #expect(after.dateOffer?.memories.map(\.id) == [kept.id], "the kept memory is unplaced, so the photo's date is offered")
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
    #expect(pages(card).map(\.id) == [dad.id], "the merged-into memory's pages are listed")
    #expect(pages(card).map(\.isChosen) == [false])
    #expect(card.dateOffer?.memories.map(\.id) == [target.id], "the merged-into memory is unplaced, so its date is offered")
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
    #expect(pages(card).map(\.id) == [maya.id])
    #expect(pages(card).map(\.isChosen) == [false])
    try f.reader.addToPage(f.subject.id, maya.id)
    let offer = try #require(card.dateOffer)
    _ = try f.reader.useDate(offer.date, for: offer.memories)
    let after = try #require(try f.reader.card(for: f.sessionID))
    #expect(pages(after).map(\.isChosen) == [true], "the page stays, chosen")
    #expect(after.dateOffer == nil)
    #expect(try f.store.memories.fetch(kept.id)?.range == .fromPhoto(day(2019, 7, 14)))
    #expect(after.hasOtherHome)
}

@Test func theReaderListsAPageThatHoldsThePhotoAndNoMemoryNames() throws {
    let f = try StoryFixture()
    let kept = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard()).memory
    let dad = try f.store.entities.insert(type: .person, title: "Dad"), maya = try f.store.entities.insert(type: .person, title: "Maya")
    try f.store.entities.link(kept.id, dad.id, relation: .mention)
    try f.store.photos.link(f.subject.id, to: .entity(maya.id))
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(pages(card).map(\.title) == ["Dad", "Maya"])
    #expect(pages(card).map(\.isChosen) == [false, true])
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

@Test func usingTheDateDoesNotDateTheMemorysChapter() throws {
    let f = try StoryFixture()
    let kept = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard()).memory
    let chapter = try CandidateActions(store: f.store).createChapter(title: "Summers", containing: kept.id)
    try f.reader.useDate(day(2019, 7, 14), for: [kept])
    #expect(try f.store.memories.fetch(kept.id)?.range == .fromPhoto(day(2019, 7, 14)))
    #expect(try f.store.chapters.chapter(id: chapter.id)?.range == .unplaced, "a chapter's range holds stated years only (S6c)")
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
    #expect(try f.store.memories.updateRange(kept.id, .fromPhoto(day(2019, 7, 14)), ifCurrently: nil))
    #expect(counter.count == 1, "the date is one transaction")
    #expect(try f.store.chapters.chapter(id: chapter.id)?.range == .unplaced, "the chapter keeps its own range (S6c)")
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
    #expect(try t.chapterEarliest() == nil, "a chapter's range holds stated years only (S6c)")
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

/// A chapter's range holds stated years only (S6c): neither the date tap nor Undo writes it.
@Test func theDateTapAndUndoLeaveTheChapterAlone() throws {
    let t = try TwoMemories()
    let changes = try t.f.reader.useDate(d, for: [t.a])
    #expect(try t.chapterEarliest() == nil)
    try t.f.reader.undoDate(changes)
    #expect(try t.chapterEarliest() == nil)
}

// MARK: - Keep puts the photo on its people's pages

@Test func keepingAMomentPutsThePhotoOnItsPeoplesPages() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad")
    _ = try f.keep(try f.pendingCard(people: ["Maya", "Dad"]))
    #expect(try f.page(maya) == [f.subject.id])
    #expect(try f.page(dad) == [f.subject.id])
    #expect(try f.store.photos.storyPages(of: f.subject.id) == [maya, dad])
}

@Test func thePhotoIsTheKeyPhotoOnAPageWithNoPhoto() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya")
    _ = try f.keep(try f.pendingCard(people: ["Maya"]))
    #expect(try f.store.photos.photos(of: .entity(maya)).map(\.role) == [.cover])
}

@Test func thePhotoGoesLastOnAPageWithPhotos() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya")
    let other = Photo(fileName: "o.jpg", sha256: "hash-o", pixelWidth: 400, pixelHeight: 300, addedAt: .now)
    try f.store.photos.insert(other, linkingTo: .entity(maya))
    _ = try f.keep(try f.pendingCard(people: ["Maya"]))
    #expect(try f.store.photos.photos(of: .entity(maya)).map(\.role) == [.cover, .attached])
    #expect(try f.page(maya) == [other.id, f.subject.id], "the story's photo is second")
}

@Test func theOwnersPageIsSkipped() throws {
    let f = try StoryFixture()
    try f.store.profile.save(Profile(displayName: "Jo", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let owner = try #require(try f.store.profile.owner()).entityID
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"], aboutSelf: true))
    #expect(try f.isNamed(owner, by: kept.id), "the moment names the owner")
    #expect(try f.page(owner).isEmpty)
    #expect(try f.page(dad) == [f.subject.id])
}

@Test func aHiddenPersonIsSkipped() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya", hidden: true), dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Maya", "Dad"]))
    #expect(try f.isNamed(maya, by: kept.id), "the moment names the hidden person")
    #expect(try f.page(maya).isEmpty)
    #expect(try f.page(dad) == [f.subject.id])
}

@Test func aPlaceIsSkipped() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"], place: "Alder Street"))
    let street = try #require(try f.store.entities.find(type: .place, title: "Alder Street")).id
    #expect(try f.isNamed(street, by: kept.id), "the moment names Alder Street")
    #expect(try f.page(street).isEmpty)
    #expect(try f.page(dad) == [f.subject.id])
}

@Test func aPageThatHoldsThePhotoKeepsItsOwnersLink() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad")
    try f.store.photos.link(f.subject.id, to: .entity(maya))
    _ = try f.keep(try f.pendingCard(people: ["Maya", "Dad"]))
    let story = try f.store.photos.storyPages(of: f.subject.id)
    #expect(!story.contains(maya), "the owner's link stays the owner's")
    #expect(story == [dad])
    #expect(try f.page(maya) == [f.subject.id], "the page holds the photo one time")
}

@Test func aPhotoTakenOffStaysOffAfterTheNextKeep() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya")
    _ = try f.keep(try f.pendingCard(people: ["Maya"]))
    #expect(try f.page(maya) == [f.subject.id])
    _ = try f.store.photos.unlink(f.subject.id, from: .entity(maya))
    _ = try f.keep(try f.pendingCard(title: "The beach", ordinal: 1, words: (1, 2), people: ["Maya"]))
    #expect(try f.page(maya).isEmpty, "a story never puts back a photo the owner took off")
}

@Test func anAssumedNameAlsoPlacesThePhoto() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya")
    let kept = try f.keep(try f.pendingCard(people: ["Maya"]))
    #expect(try f.nameLinkOrigin(kept.id, maya) == LinkOrigin.assumed.rawValue)
    #expect(try f.page(maya) == [f.subject.id])
}

@Test func aStoryWithNoPhotoWritesNoPageLink() throws {
    let f = try StoryFixture(photoSession: false)
    let maya = try f.person("Maya")
    let kept = try f.keep(try f.pendingCard(people: ["Maya"]))
    #expect(try f.isNamed(maya, by: kept.id))
    #expect(try f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link") } == 0)
}

/// The insert throws after the page links are written (the story join fails), so the whole Keep rolls back.
@Test func aFailedKeepWritesNothing() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya")
    try f.db.writer.write { try $0.execute(sql: "create trigger fail_story before insert on story begin select raise(abort, 'forced'); end") }
    let card = try f.pendingCard(people: ["Maya"], storyRef: "story-new")
    #expect(throws: (any Error).self) { try f.keep(card) }
    #expect(try f.store.memories.memories(in: f.sessionID).isEmpty, "no memory")
    #expect(try f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link where entity_id = ?", arguments: [maya.rawValue]) } == 0)
    #expect(try f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link") } == 0)
}

/// Decision 6: "Same story" writes no page link.
@Test func sameStoryWritesNoPageLink() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad")
    let target = try f.olderMemory("The old house")
    _ = try CandidateActions(store: f.store).mergeCandidate(try f.pendingCard(people: ["Maya", "Dad"]), into: target.id)
    #expect(try f.store.photos.isLinked(f.subject.id, to: .memory(target.id)), "the merged-into memory holds the photo")
    #expect(try f.isNamed(maya, by: target.id) && f.isNamed(dad, by: target.id))
    #expect(try f.page(maya).isEmpty)
    #expect(try f.page(dad).isEmpty)
}

@Test func removingThePhotoFromTheStoryRemovesItsStoryLinks() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad")
    _ = try f.keep(try f.pendingCard(people: ["Maya"]))
    #expect(try f.store.photos.storyPages(of: f.subject.id) == [maya])
    try f.store.photos.link(f.subject.id, to: .entity(dad))
    #expect(try f.store.photos.letGo(of: f.sessionID) == nil)
    #expect(try f.page(maya).isEmpty, "the story's link goes with the story")
    #expect(try f.page(dad) == [f.subject.id], "the owner's link stays")
    #expect(try f.store.photos.photo(id: f.subject.id) != nil)
}

@Test func removingThePhotoKeepsStoryLinksWhenAnotherSessionPointsAtIt() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya")
    _ = try f.keep(try f.pendingCard(people: ["Maya"]))
    let (other, _) = try StoreFixtures.session(in: f.store.sessions, segments: ["the beach"])
    var row = try #require(try f.store.sessions.fetch(other))
    row.subjectPhotoID = f.subject.id; row.startedFrom = .photo
    try f.store.sessions.update(row)
    _ = try f.store.photos.letGo(of: f.sessionID)
    #expect(try f.page(maya) == [f.subject.id])
    #expect(try f.store.photos.storyPages(of: f.subject.id) == [maya])
}

// MARK: - Pages the story chose

private func storyCard(_ maya: Entity, holds: Bool = true, story: Set<EntityID>) -> PhotoStoryCard {
    let m = memory("A")
    return PhotoStory.card(photo: photo(), sessionMemories: [m], holding: [m.id], linked: [m.id: [maya]],
                           pagesWithPhoto: holds ? [maya] : [], ownerEntity: nil, storyPages: story,
                           hasPendingMoments: false, hasOtherHome: false)
}

@Test func aPageTheStoryChoseReadsAddedByThisStory() {
    let maya = entity("Maya")
    let page = pages(storyCard(maya, story: [maya.id]))[0]
    #expect(page.isChosen && page.byStory)
    #expect(page.stateValue == "added by this story")
}

@Test func aPageTheOwnerTappedReadsAdded() {
    let maya = entity("Maya")
    let page = pages(storyCard(maya, story: []))[0]
    #expect(page.isChosen && !page.byStory)
    #expect(page.stateValue == "added")
}

@Test func theLineNamesTheStorysChoiceWhileOnePageHasIt() {
    let maya = entity("Maya")
    #expect(storyCard(maya, story: [maya.id]).pagesLine
            == "The people in this story have this photo on their pages. Tap to take it off, or to add it to another page.")
}

@Test func theLineIsThePlainOneWithNoStoryPage() {
    let maya = entity("Maya")
    #expect(storyCard(maya, story: []).pagesLine == "Tap to add. Tap again to take it off.")
}

@Test func byStoryIsFalseForAPageThatDoesNotHoldThePhoto() {
    let maya = entity("Maya")
    let card = storyCard(maya, holds: false, story: [maya.id])
    let page = pages(card)[0]
    #expect(!page.isChosen && !page.byStory)
    #expect(page.stateValue == "not added")
    #expect(card.pagesLine == "Tap to add. Tap again to take it off.")
}

@Test func theReaderCardFollowsTheStorysChoiceTheOwnersRemovalAndTheOwnersAdd() throws {
    let f = try StoryFixture()
    try f.store.sessions.setStatus(.extracted, for: f.segments[0].id)
    _ = try CandidateActions(store: f.store).acceptMemory(try f.pendingCard(people: ["Maya"]))
    let kept = try #require(try f.reader.card(for: f.sessionID))
    let mayaPage = try #require(pages(kept).first { $0.title == "Maya" })
    #expect(mayaPage.isChosen && mayaPage.byStory)
    // The owner's removal goes through the store call PhotoLibrary.remove makes.
    _ = try f.store.photos.unlink(f.subject.id, from: .entity(mayaPage.id))
    let removed = try #require(try f.reader.card(for: f.sessionID))
    let after = try #require(pages(removed).first { $0.title == "Maya" })
    #expect(!after.isChosen && !after.byStory)
    #expect(removed.pagesLine == "Tap to add. Tap again to take it off.")
    try f.reader.addToPage(f.subject.id, mayaPage.id)
    let added = try #require(try f.reader.card(for: f.sessionID))
    let again = try #require(pages(added).first { $0.title == "Maya" })
    #expect(again.isChosen && !again.byStory)
}

// MARK: - The photo follows a moved name

private extension StoryFixture {
    var actions: PersonLinkActions { PersonLinkActions(store: store) }

    /// The memory's mention of the person, as the "Who is this?" sheet gets it.
    func nameLink(_ memory: Memory, _ person: EntityID) throws -> PersonLink {
        try #require(try store.personLinks.links(to: PersonID(rawValue: person.rawValue)).first { $0.memoryID == memory.id && $0.relation == .mention })
    }

    /// The origin of the page's link to the story's photo, as stored; nil for the owner's link or no link.
    func pageLinkOrigin(_ entity: EntityID) throws -> String? {
        try db.writer.read { try String.fetchOne($0, sql: "select origin from photo_link where photo_id = ? and entity_id = ?",
                                                 arguments: [subject.id.rawValue, entity.rawValue]) }
    }

    /// Two moments of the story that name Dad, kept.
    func twoMomentsNamingDad() throws -> (Memory, Memory) {
        (try keep(try pendingCard(people: ["Dad"])), try keep(try pendingCard(title: "The beach", ordinal: 1, words: (1, 2), people: ["Dad"])))
    }
}

private func entityID(_ person: PersonID?) throws -> EntityID { EntityID(rawValue: try #require(person).rawValue) }
private func personID(_ entity: EntityID) -> PersonID { PersonID(rawValue: entity.rawValue) }

@Test func movingANameMovesTheStorysPhoto() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    #expect(try f.nameLinkOrigin(kept.id, dad) == LinkOrigin.assumed.rawValue)
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .someoneNew, wholeGroup: false)
    let new = try entityID(receipt.createdPerson)
    #expect(try f.page(new) == [f.subject.id])
    #expect(try f.pageLinkOrigin(new) == PhotoLinkOrigin.story.rawValue)
    #expect(try f.page(dad).isEmpty)
    #expect(receipt.photoPages == PhotoPageChange(photo: f.subject.id, added: [new], removed: [dad]))
}

@Test func aMoveToAPersonOnFileMovesThePhoto() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad"), maya = try f.person("Maya")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .person(personID(maya)), wholeGroup: false)
    #expect(try f.page(maya) == [f.subject.id])
    #expect(try f.pageLinkOrigin(maya) == PhotoLinkOrigin.story.rawValue)
    #expect(try f.page(dad).isEmpty)
    #expect(receipt.photoPages == PhotoPageChange(photo: f.subject.id, added: [maya], removed: [dad]))
}

@Test func notAPersonRemovesTheStorysLinkAndAddsNone() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .notAPerson, wholeGroup: false)
    #expect(try f.page(dad).isEmpty)
    #expect(try f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link where entity_id is not null") } == 0)
    #expect(receipt.photoPages == PhotoPageChange(photo: f.subject.id, added: [], removed: [dad]))
}

@Test func theFirstPersonKeepsThePhotoWhileAnotherMomentNamesThem() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    let (first, _) = try f.twoMomentsNamingDad()
    let receipt = try f.actions.move(try f.nameLink(first, dad), to: .someoneNew, wholeGroup: false)
    let new = try entityID(receipt.createdPerson)
    #expect(try f.page(dad) == [f.subject.id], "the other moment still names Dad")
    #expect(try f.page(new) == [f.subject.id])
    #expect(receipt.photoPages == PhotoPageChange(photo: f.subject.id, added: [new], removed: []))
}

@Test func aMoveLeavesAnOwnersLink() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    try f.store.photos.link(f.subject.id, to: .entity(dad))
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .someoneNew, wholeGroup: false)
    #expect(try f.page(dad) == [f.subject.id], "the owner put the photo there before the story")
    #expect(try f.pageLinkOrigin(dad) == nil)
    #expect(receipt.photoPages?.removed == [])
}

@Test func aMoveDoesNotAddToADeclinedPage() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad"), maya = try f.person("Maya")
    try f.store.photos.link(f.subject.id, to: .entity(maya))
    _ = try f.store.photos.unlink(f.subject.id, from: .entity(maya))
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .person(personID(maya)), wholeGroup: false)
    #expect(try f.page(maya).isEmpty, "the owner took the photo off Maya's page")
    #expect(receipt.photoPages?.added == [])
}

@Test func aMoveInAStoryWithNoPhotoTouchesNoPhotoLink() throws {
    let f = try StoryFixture(photoSession: false)
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .someoneNew, wholeGroup: false)
    #expect(receipt.photoPages == nil)
}

/// Decision 10: the move acts only when the moved moment holds the photo.
@Test func aMoveOfAMomentThatDoesNotHoldThePhotoTouchesNoPhotoLink() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    _ = try f.store.photos.unlink(f.subject.id, from: .memory(kept.id))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .someoneNew, wholeGroup: false)
    #expect(receipt.photoPages == nil)
    #expect(try f.page(dad) == [f.subject.id], "the page keeps the photo, as after a removed moment")
    #expect(try f.page(try entityID(receipt.createdPerson)).isEmpty)
}

@Test func theRemovalRecordsNoDecline() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    _ = try f.actions.move(try f.nameLink(kept, dad), to: .notAPerson, wholeGroup: false)
    #expect(try f.page(dad).isEmpty)
    #expect(try !f.store.photos.isDeclined(f.subject.id, on: dad))
    #expect(try f.store.photos.photo(id: f.subject.id) != nil, "the session still points at the photo")
}

@Test func undoPutsThePhotoBack() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .someoneNew, wholeGroup: false)
    let new = try #require(receipt.createdPerson)
    try f.actions.undo(receipt)
    #expect(try f.page(dad) == [f.subject.id])
    #expect(try f.pageLinkOrigin(dad) == PhotoLinkOrigin.story.rawValue)
    #expect(try f.store.people.person(id: new) == nil, "the new person is gone, as today")
    #expect(try f.store.photos.storyPages(of: f.subject.id) == [dad])
}

/// A guessed person the move empties goes; Undo brings the person back first, then the photo link.
@Test func undoPutsThePhotoBackOnAGuessedPersonTheMoveRemoved() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya")
    let kept = try f.keep(try f.pendingCard(people: ["Tomas"]))
    let tomas = try #require(try f.store.personLinks.links(of: kept.id).first).person
    #expect(tomas.createdByGuess)
    #expect(try f.page(tomas.entityID) == [f.subject.id])
    let receipt = try f.actions.move(try f.nameLink(kept, tomas.entityID), to: .person(personID(maya)), wholeGroup: false)
    #expect(try f.store.people.person(id: tomas.id) == nil, "the photo the story put there does not hold the guess")
    #expect(receipt.photoPages == PhotoPageChange(photo: f.subject.id, added: [maya], removed: [tomas.entityID]))
    try f.actions.undo(receipt)
    #expect(try f.store.people.person(id: tomas.id) != nil)
    #expect(try f.page(tomas.entityID) == [f.subject.id])
    #expect(try f.pageLinkOrigin(tomas.entityID) == PhotoLinkOrigin.story.rawValue)
    #expect(try f.page(maya).isEmpty)
}

@Test func undoLeavesALinkTheOwnerMadeAfterTheMove() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad"), maya = try f.person("Maya")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .person(personID(maya)), wholeGroup: false)
    _ = try f.store.photos.unlink(f.subject.id, from: .entity(maya))
    try f.store.photos.link(f.subject.id, to: .entity(maya))
    #expect(try f.pageLinkOrigin(maya) == nil, "now the owner's link")
    try f.actions.undo(receipt)
    #expect(try f.page(maya) == [f.subject.id], "Undo leaves the owner's link")
    #expect(try f.page(dad) == [f.subject.id])
}

@Test func undoDoesNotBringBackAPhotoTheOwnerTookOff() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad"), maya = try f.person("Maya")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .person(personID(maya)), wholeGroup: false)
    try f.store.photos.link(f.subject.id, to: .entity(dad))
    _ = try f.store.photos.unlink(f.subject.id, from: .entity(dad))
    try f.actions.undo(receipt)
    #expect(try f.page(dad).isEmpty, "the owner took the photo off Dad's page")
    #expect(try f.page(maya).isEmpty, "the story's link to Maya goes with Undo")
}

/// Fix round 1: one photo can be the subject of two sessions. A story link stays while any memory that holds the photo names the person.
@Test func aMoveLeavesTheLinkWhileAnotherStoryOfTheSamePhotoNamesThePerson() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad"), maya = try f.person("Maya")
    _ = try f.keep(try f.pendingCard(people: ["Dad"]))
    let (second, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["the beach"])
    var row = try #require(try f.store.sessions.fetch(second))
    row.subjectPhotoID = f.subject.id; row.startedFrom = .photo
    try f.store.sessions.update(row)
    let other = try f.keep(try f.pendingCard(title: "The beach", people: ["Dad"], segment: segments[0].id))
    let receipt = try f.actions.move(try f.nameLink(other, dad), to: .person(personID(maya)), wholeGroup: false)
    #expect(try f.page(dad) == [f.subject.id], "the first session's moment still names Dad")
    #expect(try f.pageLinkOrigin(dad) == PhotoLinkOrigin.story.rawValue)
    #expect(receipt.photoPages?.removed == [])
}

@Test func undoLeavesTheNewPersonsPhotoWhileAnotherKeptMomentNamesThem() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad"), maya = try f.person("Maya")
    let kept = try f.keep(try f.pendingCard(people: ["Dad"]))
    let receipt = try f.actions.move(try f.nameLink(kept, dad), to: .person(personID(maya)), wholeGroup: false)
    #expect(receipt.photoPages?.added == [maya])
    _ = try f.keep(try f.pendingCard(title: "The beach", ordinal: 1, words: (1, 2), people: ["Maya"]))
    try f.actions.undo(receipt)
    #expect(try f.page(maya) == [f.subject.id], "the other kept moment still names Maya")
    #expect(try f.page(dad) == [f.subject.id])
}

// MARK: - Done and Edit (spec part 3)

private func shown(_ card: PhotoStoryCard, keeping kept: Set<EntityID> = []) -> [String] {
    card.shownPageGroups(keeping: kept).flatMap(\.pages).map(\.title)
}

@Test func aNewStoryStartsOpen() throws {
    let f = try StoryFixture()
    let maya = try f.person("Maya"), dad = try f.person("Dad")
    _ = try f.keep(try f.pendingCard(people: ["Maya", "Dad"]))
    _ = try f.store.photos.unlink(f.subject.id, from: .entity(dad))
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(!card.pagesDone)
    #expect(card.shownPageGroups(keeping: []) == card.pageGroups, "open shows every chip, filled or empty")
    #expect(shown(card) == ["Dad", "Maya"])
    #expect(!card.showsNoOtherPageSentence(keeping: []))
    #expect(card.shownPagesLine == card.pagesLine, "open shows the line")
    #expect(pages(card).first { $0.id == maya }?.isChosen == true)
}

@Test func doneShowsOnlyTheChosenPages() {
    let m = memory("The picnic"), maya = entity("Maya"), dad = entity("Dad"), beach = entity("The beach", type: .place)
    let result = card(memories: [m], linked: [m.id: [maya, dad, beach]], pagesWithPhoto: [maya], pagesDone: true)
    #expect(result.pagesDone)
    #expect(shown(result) == ["Maya"])
    #expect(result.shownPageGroups(keeping: []).map(\.type) == [.person], "a group with no chosen page is left out")
    #expect(!result.showsNoOtherPageSentence(keeping: []))
    #expect(result.shownPagesLine == nil, "done shows no line")
}

@Test func doneKeepsAPageTheOwnerJustEmptied() {
    let m = memory("The picnic"), maya = entity("Maya"), dad = entity("Dad")
    let result = card(memories: [m], linked: [m.id: [maya, dad]], pagesWithPhoto: [maya], pagesDone: true)
    #expect(shown(result, keeping: [dad.id]) == ["Dad", "Maya"], "the emptied chip stays, in its place")
    #expect(result.shownPageGroups(keeping: [dad.id]).flatMap(\.pages).map(\.isChosen) == [false, true], "and shows it is empty")
    #expect(!result.showsNoOtherPageSentence(keeping: [dad.id]))
}

@Test func doneWithNoChosenPageShowsTheSentence() {
    let m = memory("The picnic"), maya = entity("Maya")
    let done = card(memories: [m], linked: [m.id: [maya]], pagesDone: true)
    #expect(done.shownPageGroups(keeping: []).isEmpty)
    #expect(done.showsNoOtherPageSentence(keeping: []))
    #expect(!done.showsNoOtherPageSentence(keeping: [maya.id]), "a kept chip is still on screen")
    #expect(!card(memories: [m], linked: [m.id: [maya]]).showsNoOtherPageSentence(keeping: []), "open shows the chips instead")
    #expect(PhotoStoryCard.noOtherPageSentence == "This photo is on no other page.")
    #expect(PhotoStoryCard.doneTitle == "Done")
    #expect(PhotoStoryCard.editTitle == "Edit")
}

@Test func editShowsEveryPageAgain() throws {
    let f = try StoryFixture()
    _ = try f.person("Maya"); let dad = try f.person("Dad")
    _ = try f.keep(try f.pendingCard(people: ["Maya", "Dad"]))
    _ = try f.store.photos.unlink(f.subject.id, from: .entity(dad))
    try f.reader.setPagesDone(true, for: f.sessionID)
    #expect(shown(try #require(try f.reader.card(for: f.sessionID))) == ["Maya"])
    try f.reader.setPagesDone(false, for: f.sessionID)
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(!card.pagesDone)
    #expect(shown(card) == ["Dad", "Maya"])
}

@Test func theStateIsStoredForTheStory() throws {
    let f = try StoryFixture()
    let (other, _) = try StoreFixtures.session(in: f.store.sessions, segments: ["the beach"])
    try f.reader.setPagesDone(true, for: f.sessionID)
    let fresh = PhotoStoryReader(store: ExtractionStore(f.db))
    #expect(try #require(try fresh.card(for: f.sessionID)).pagesDone)
    #expect(try f.store.sessions.fetch(f.sessionID)?.photoPagesDone == true)
    #expect(try f.store.sessions.fetch(other)?.photoPagesDone == false, "another story stays open")
}

@Test func aPageTheStoryChoosesAfterDoneShows() throws {
    let f = try StoryFixture()
    let dad = try f.person("Dad")
    try f.reader.setPagesDone(true, for: f.sessionID)
    _ = try f.keep(try f.pendingCard(people: ["Dad"]))
    let card = try #require(try f.reader.card(for: f.sessionID))
    #expect(card.pagesDone)
    #expect(card.shownPageGroups(keeping: []).flatMap(\.pages).map(\.id) == [dad], "its chip is filled, so it shows")
    #expect(card.shownPageGroups(keeping: []).flatMap(\.pages).map(\.byStory) == [true])
}

@Test func everyPagesLineIsReserved() {
    let m = memory("The picnic"), maya = entity("Maya")
    let byStory = PhotoStory.card(photo: photo(), sessionMemories: [m], holding: [m.id], linked: [m.id: [maya]], pagesWithPhoto: [maya],
                                  ownerEntity: nil, storyPages: [maya.id], hasPendingMoments: false, hasOtherHome: false)
    let tap = card(memories: [m], linked: [m.id: [maya]])
    #expect(Set(PhotoStoryCard.allPagesLines) == [byStory.pagesLine, tap.pagesLine])
}
