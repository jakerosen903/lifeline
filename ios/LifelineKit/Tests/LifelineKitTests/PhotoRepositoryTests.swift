import Foundation
import Testing
import GRDB
@testable import LifelineKit

/// Counts the statements one connection runs.
private final class StatementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private func at(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n)) }

private func photo(_ name: String, at n: Int = 0) -> Photo {
    Photo(fileName: "\(name).jpg", sha256: "hash-\(name)", pixelWidth: 400, pixelHeight: 300, addedAt: at(n))
}

private struct Fixture {
    let db: AppDatabase
    let store: ExtractionStore
    let segments: [Segment]
    let sessionID: SessionID
    var photos: PhotoRepository { store.photos }

    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        (sessionID, segments) = try StoreFixtures.session(in: store.sessions, segments: ["the tree house", "the old house"])
    }

    func person(_ name: String) throws -> Entity { try store.entities.insert(type: .person, title: name) }

    func memory(_ title: String, segment: Int) throws -> Memory {
        try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[segment].id, title: title)
    }
}

@Test func takenAtReadsTheCameraFormOnly() {
    #expect(PhotoTakenAt(exif: "2012:06:14 15:32:10")?.stored == "2012-06-14T15:32:10")
    #expect(PhotoTakenAt(exif: "0000:00:00 00:00:00") == nil)
    #expect(PhotoTakenAt(exif: "2012-06-14") == nil)
    #expect(PhotoTakenAt(exif: "+012:06:14 15:32:10") == nil, "digits only: no sign")
    #expect(PhotoTakenAt(exif: "2012:06:14 +5:32:10") == nil, "digits only: no sign")
    #expect(PhotoTakenAt(stored: "2012-06-14T15:32:10")?.date == CivilDate(year: 2012, month: 6, day: 14))
}

@Test func theFirstPhotoIsTheCoverAndTheRestFollowInOrder() throws {
    let f = try Fixture(), maya = try f.person("Maya")
    let a = photo("a", at: 1), b = photo("b", at: 2), c = photo("c", at: 3)
    try f.photos.insert(a, linkingTo: .entity(maya.id)); try f.photos.insert(b, linkingTo: .entity(maya.id)); try f.photos.insert(c, linkingTo: .entity(maya.id))
    #expect(try f.photos.photos(of: .entity(maya.id)).map(\.id) == [a.id, b.id, c.id])
    #expect(try f.photos.photos(of: .entity(maya.id)).map(\.isCover) == [true, false, false])
    try f.photos.setCover(c.id, of: .entity(maya.id))
    #expect(try f.photos.photos(of: .entity(maya.id)).map(\.id) == [c.id, a.id, b.id])
}

@Test func aRowRoundTripsEveryColumn() throws {
    let f = try Fixture(), treeHouse = try f.memory("The tree house", segment: 0)
    var a = photo("a", at: 5)
    a.takenAt = PhotoTakenAt(exif: "2012:06:14 15:32:10"); a.takenOrigin = .exif
    a.lat = 0.5; a.lon = -30.0; a.locationOrigin = .exif; a.assetLocalID = "invented/L0/001"
    try f.photos.insert(a, linkingTo: .memory(treeHouse.id))
    #expect(try f.photos.photo(id: a.id) == a)
    #expect(try f.photos.photo(sha256: a.sha256) == a)
    #expect(try f.photos.photo(sha256: "no such hash") == nil)
}

@Test func linkingTwiceChangesNothing() throws {
    let f = try Fixture(), maya = try f.person("Maya"), dad = try f.person("Dad")
    let a = photo("a")
    try f.photos.insert(a, linkingTo: .entity(maya.id)); try f.photos.link(a.id, to: .entity(dad.id)); try f.photos.link(a.id, to: .entity(maya.id))
    #expect(try f.photos.photos(of: .entity(maya.id)).count == 1)
    #expect(try f.photos.photos(of: .entity(dad.id)).map(\.isCover) == [true])
}

@Test func removingTheCoverPassesItToTheOldestLeft() throws {
    let f = try Fixture(), maya = try f.person("Maya")
    let a = photo("a", at: 1), b = photo("b", at: 2), c = photo("c", at: 3)
    for p in [a, b, c] { try f.photos.insert(p, linkingTo: .entity(maya.id)) }
    #expect(try f.photos.unlink(a.id, from: .entity(maya.id)) == a, "no page left: the row goes")
    #expect(try f.photos.photos(of: .entity(maya.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(b.id.rawValue) cover", "\(c.id.rawValue) attached"])
    _ = try f.photos.unlink(b.id, from: .entity(maya.id)); _ = try f.photos.unlink(c.id, from: .entity(maya.id))
    #expect(try f.photos.photos(of: .entity(maya.id)).isEmpty)
    #expect(try f.photos.covers(type: .person)[maya.id] == nil)
}

@Test func removingAnAttachedPhotoKeepsTheCover() throws {
    let f = try Fixture(), maya = try f.person("Maya")
    let a = photo("a", at: 1), b = photo("b", at: 2)
    for p in [a, b] { try f.photos.insert(p, linkingTo: .entity(maya.id)) }
    _ = try f.photos.unlink(b.id, from: .entity(maya.id))
    #expect(try f.photos.photos(of: .entity(maya.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(a.id.rawValue) cover"])
}

@Test func unlinkingFromOnePageKeepsTheOther() throws {
    let f = try Fixture(), maya = try f.person("Maya"), dad = try f.person("Dad")
    let a = photo("a")
    try f.photos.insert(a, linkingTo: .entity(maya.id)); try f.photos.link(a.id, to: .entity(dad.id))
    #expect(try f.photos.unlink(a.id, from: .entity(maya.id)) == nil)
    #expect(try f.photos.photo(id: a.id) == a)
}

@Test func deletingASubjectRemovesItsLinks() throws {
    let f = try Fixture(), maya = try f.person("Maya"), treeHouse = try f.memory("The tree house", segment: 0)
    let a = photo("a"), b = photo("b")
    try f.photos.insert(a, linkingTo: .entity(maya.id)); try f.photos.insert(b, linkingTo: .memory(treeHouse.id))
    try f.store.entities.delete(maya.id); try f.store.memories.delete(treeHouse.id)
    #expect(try f.photos.deleteUnlinked().map(\.id).sorted { $0.rawValue < $1.rawValue } == [a.id, b.id].sorted { $0.rawValue < $1.rawValue })
    #expect(try f.photos.fileNames().isEmpty)
}

@Test func foldingAMemoryMovesItsPhotos() throws {
    let f = try Fixture()
    let t = try f.memory("The tree house", segment: 0), s = try f.memory("The tree house again", segment: 1)
    let x = photo("x", at: 1), y = photo("y", at: 2), z = photo("z", at: 3)
    try f.photos.insert(x, linkingTo: .memory(t.id))
    try f.photos.insert(y, linkingTo: .memory(s.id)); try f.photos.insert(z, linkingTo: .memory(s.id))
    try f.store.memories.fold(s, into: t)
    #expect(try f.photos.photos(of: .memory(t.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" }
            == ["\(x.id.rawValue) cover", "\(y.id.rawValue) attached", "\(z.id.rawValue) attached"])
    #expect(try f.photos.deleteUnlinked().isEmpty, "nothing is orphaned by a merge")
}

@Test func foldingDoesNotLinkASharedPhotoTwice() throws {
    let f = try Fixture()
    let t = try f.memory("The tree house", segment: 0), s = try f.memory("The tree house again", segment: 1)
    let y = photo("y"), shared = photo("shared", at: 1)
    try f.photos.insert(y, linkingTo: .memory(s.id)); try f.photos.insert(shared, linkingTo: .memory(s.id)); try f.photos.link(shared.id, to: .memory(t.id))
    try f.store.memories.fold(s, into: t)
    // The target held `shared` as its cover already; `y` arrives behind it, and `shared` is not linked twice.
    #expect(try f.photos.photos(of: .memory(t.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(shared.id.rawValue) cover", "\(y.id.rawValue) attached"])
}

@Test func coversReadEveryPersonAtOnce() throws {
    let f = try Fixture()
    let counter = StatementCounter()
    try f.db.writer.write { db in db.trace { _ in counter.add() } }
    func addPeople(_ names: [String], from start: Int) throws -> Photo {
        var first: Photo?
        for (i, name) in names.enumerated() {
            let p = photo("p\(start + i)", at: start + i)
            try f.photos.insert(p, linkingTo: .entity(try f.person(name).id))
            first = first ?? p
        }
        return first!
    }
    func statementsForOneRead() throws -> Int {
        let before = counter.count
        _ = try f.photos.covers(type: .person)
        return counter.count - before
    }
    let a = try addPeople(["Maya", "Dad", "Lena"], from: 0)
    let statementsForFew = try statementsForOneRead()
    _ = try addPeople((1...30).map { "Person\($0)" }, from: 100)
    let statementsForMany = try statementsForOneRead()
    #expect(statementsForFew > 0)
    #expect(statementsForMany == statementsForFew)
    let maya = try #require(try f.store.entities.find(type: .person, title: "Maya"))
    #expect(try f.photos.covers(type: .person)[maya.id] == a)
    #expect(try f.photos.covers(type: .place).isEmpty)
}

@Test func aHiddenPersonHasNoCoverInTheGrid() throws {
    let f = try Fixture(), maya = try f.person("Maya")
    try f.photos.insert(photo("a"), linkingTo: .entity(maya.id))
    try f.store.entities.setHidden(maya.id, true)
    #expect(try f.photos.covers(type: .person)[maya.id] == nil)
}

@Test func makingAnUnlinkedPhotoTheCoverChangesNothing() throws {
    let f = try Fixture(), maya = try f.person("Maya"), dad = try f.person("Dad")
    let a = photo("a", at: 1), b = photo("b", at: 2)
    try f.photos.insert(a, linkingTo: .entity(maya.id)); try f.photos.insert(b, linkingTo: .entity(dad.id))
    try f.photos.setCover(b.id, of: .entity(maya.id))
    #expect(try f.photos.photos(of: .entity(maya.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(a.id.rawValue) cover"])
    #expect(try f.photos.photos(of: .entity(dad.id)).map(\.isCover) == [true])
}

@Test func unlinkingAPhotoThatIsNotOnThePageChangesNothing() throws {
    let f = try Fixture(), maya = try f.person("Maya"), dad = try f.person("Dad")
    let a = photo("a", at: 1), b = photo("b", at: 2)
    try f.photos.insert(a, linkingTo: .entity(maya.id)); try f.photos.insert(b, linkingTo: .entity(dad.id))
    #expect(try f.photos.unlink(b.id, from: .entity(maya.id)) == nil)
    #expect(try f.photos.photo(id: b.id) == b, "the row stays")
    #expect(try f.photos.photos(of: .entity(maya.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(a.id.rawValue) cover"])
    // A row with no link at all is the sweep's to delete, not unlink's.
    let loose = photo("loose", at: 3)
    try f.db.writer.write { try loose.insert($0) }
    #expect(try f.photos.unlink(loose.id, from: .entity(maya.id)) == nil)
    #expect(try f.photos.photo(id: loose.id) == loose)
}

@Test func foldingGivesTheSourceCoverToATargetWithNone() throws {
    let f = try Fixture()
    let t = try f.memory("The tree house", segment: 0), s = try f.memory("The tree house again", segment: 1)
    let y = photo("y", at: 1), z = photo("z", at: 2)
    try f.photos.insert(y, linkingTo: .memory(s.id)); try f.photos.insert(z, linkingTo: .memory(s.id))
    try f.store.memories.fold(s, into: t)
    #expect(try f.photos.photos(of: .memory(t.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(y.id.rawValue) cover", "\(z.id.rawValue) attached"])
}

// MARK: - A session as a home (photo story)

extension Fixture {
    /// A session that points at `photo`.
    @discardableResult
    func photoSession(pointingAt photo: Photo) throws -> SessionID {
        let session = Session(id: SessionID(), startedAt: at(5), endedAt: nil, audioPath: "photo.m4a", stageLog: "[]", landingChoiceMade: false,
                              subjectPhotoID: photo.id, startedFrom: .photo)
        try store.sessions.insert(session)
        return session.id
    }
}

@Test func aPhotoAStoryPointsAtSurvivesItsLastUnlink() throws {
    let f = try Fixture(), maya = try f.person("Maya")
    let a = photo("a")
    try f.photos.insert(a, linkingTo: .entity(maya.id))
    try f.photoSession(pointingAt: a)
    #expect(try f.photos.unlink(a.id, from: .entity(maya.id)) == nil)
    #expect(try f.photos.photo(id: a.id) != nil)
}

@Test func deleteUnlinkedKeepsAPhotoAStoryPointsAt() throws {
    let f = try Fixture()
    let a = photo("a")
    try f.photos.insert(a)
    try f.photoSession(pointingAt: a)
    #expect(try f.photos.deleteUnlinked().isEmpty)
    #expect(try f.photos.photo(id: a.id) != nil)
}

@Test func lettingGoKeepsAPhotoWithAPage() throws {
    let f = try Fixture(), maya = try f.person("Maya")
    let a = photo("a")
    try f.photos.insert(a, linkingTo: .entity(maya.id))
    let session = try f.photoSession(pointingAt: a)
    #expect(try f.photos.letGo(of: session) == nil)
    #expect(try f.photos.photo(id: a.id) != nil)
    #expect(try f.photos.subjectPhoto(of: session) == nil)
}

@Test func lettingGoOfThePhotoWithNoOtherHomeReturnsItsRow() throws {
    let f = try Fixture()
    let a = photo("a")
    try f.photos.insert(a)
    let session = try f.photoSession(pointingAt: a)
    #expect(try f.photos.subjectPhoto(of: session) == a)
    #expect(try f.photos.letGo(of: session) == a)
    #expect(try f.photos.photo(id: a.id) == nil)
    #expect(try f.photos.letGo(of: session) == nil, "letting go twice changes nothing")
}

@Test func twoStoriesAboutOnePhotoEachHoldIt() throws {
    let f = try Fixture()
    let a = photo("a")
    try f.photos.insert(a)
    let first = try f.photoSession(pointingAt: a), second = try f.photoSession(pointingAt: a)
    #expect(try f.photos.letGo(of: first) == nil)
    #expect(try f.photos.subjectPhoto(of: second)?.id == a.id)
    #expect(try f.photos.letGo(of: second) == a)
}

@Test func hasOtherHomeIgnoresMemoriesOnlyFromThisSession() throws {
    let f = try Fixture(), dad = try f.person("Dad")
    let a = photo("a")
    try f.photos.insert(a)
    // The fixture's own session tells memory A, and it is the one that points at the photo.
    let session = f.sessionID
    var row = try #require(try f.store.sessions.fetch(session))
    row.subjectPhotoID = a.id; row.startedFrom = .photo
    try f.store.sessions.update(row)
    let memoryA = try f.memory("The tree house", segment: 0)
    try f.photos.link(a.id, to: .memory(memoryA.id))
    #expect(try f.photos.hasOtherHome(a.id, than: session) == false, "a memory told only in this session is this story's own")
    try f.photos.link(a.id, to: .entity(dad.id))
    #expect(try f.photos.hasOtherHome(a.id, than: session) == true)
    _ = try f.photos.unlink(a.id, from: .entity(dad.id))
    #expect(try f.photos.hasOtherHome(a.id, than: session) == false)
    // Memory B has a span in another session.
    let (_, other) = try StoreFixtures.session(in: f.store.sessions, segments: ["the old house"])
    let memoryB = try StoreFixtures.memory(in: f.store.memories, candidates: f.store.candidates, segment: other[0].id, title: "The old house")
    try f.photos.link(a.id, to: .memory(memoryB.id))
    #expect(try f.photos.hasOtherHome(a.id, than: session) == true)
}

@Test func anotherSessionPointingAtThePhotoIsAnotherHome() throws {
    let f = try Fixture()
    let a = photo("a")
    try f.photos.insert(a)
    let first = try f.photoSession(pointingAt: a)
    #expect(try f.photos.hasOtherHome(a.id, than: first) == false)
    try f.photoSession(pointingAt: a)
    #expect(try f.photos.hasOtherHome(a.id, than: first) == true)
}

// MARK: - A kept memory gets the session's photo

private extension Fixture {
    /// Makes the fixture's own session a story about a new photo.
    func makeSessionAPhotoSession(_ name: String = "story") throws -> Photo {
        let subject = photo(name)
        try photos.insert(subject)
        var row = try #require(try store.sessions.fetch(sessionID))
        row.subjectPhotoID = subject.id; row.startedFrom = .photo
        try store.sessions.update(row)
        return subject
    }

    /// A pending memory card over the first two words of segment `segment`.
    func card(segment: Int = 0, ordinal: Int = 0, title: String = "The tree house") throws -> Candidate {
        let out = MemoryOut(ref: "m1", title: title, quote: "the tree", segmentSpan: WordSpan(startWord: 0, endWord: 1),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        // Ordinal 7: the fixture's own memories hold ordinal 0 on their segments.
        let card = StoreFixtures.candidate(segments[segment].id, ordinal: 7 + ordinal, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(card)
        return card
    }

    var actions: CandidateActions { CandidateActions(store: store) }

    func links(of memory: MemoryID) throws -> [String] {
        try photos.photos(of: .memory(memory)).map { "\($0.id.rawValue) \($0.role.rawValue)" }
    }
}

@Test func keepingAMemoryFromAPhotoSessionLinksThePhoto() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let kept = try f.actions.acceptMemory(try f.card()).memory
    #expect(try f.photos.photos(of: .memory(kept.id)).map(\.photo.id) == [subject.id])
}

@Test func theFirstPhotoOnAMemoryIsItsCover() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let kept = try f.actions.acceptMemory(try f.card()).memory
    #expect(try f.photos.photos(of: .memory(kept.id)).map(\.role) == [.cover])
    #expect(try f.photos.photos(of: .memory(kept.id)).first?.photo.id == subject.id)
}

@Test func aMemoryThatHasACoverKeepsIt() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let target = try f.memory("The old house", segment: 1), cover = photo("cover", at: 1)
    try f.photos.insert(cover, linkingTo: .memory(target.id))
    _ = try f.actions.mergeCandidate(try f.card(), into: target.id)
    #expect(try f.links(of: target.id) == ["\(cover.id.rawValue) cover", "\(subject.id.rawValue) attached"])
}

@Test func mergingATellingFromAPhotoSessionLinksThePhotoToTheTarget() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let target = try f.memory("The old house", segment: 1)
    _ = try f.actions.mergeCandidate(try f.card(), into: target.id)
    #expect(try f.links(of: target.id) == ["\(subject.id.rawValue) cover"])
}

@Test func aGroupMergeLinksThePhotoOnce() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let first = try f.memory("The old house", segment: 1), second = try f.memory("The old house again", segment: 0)
    let result = try f.actions.mergeGroup(try f.card(), into: [first.id, second.id])
    #expect(try f.links(of: result.receipt.target) == ["\(subject.id.rawValue) cover"])
    let count = try f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link where photo_id = ?", arguments: [subject.id.rawValue]) }
    #expect(count == 1)
}

@Test func aSessionWithNoPhotoLinksNothing() throws {
    let f = try Fixture()
    let kept = try f.actions.acceptMemory(try f.card()).memory
    #expect(try f.links(of: kept.id).isEmpty)
    let target = try f.memory("The old house", segment: 1)
    _ = try f.actions.mergeCandidate(try f.card(ordinal: 1), into: target.id)
    #expect(try f.links(of: target.id).isEmpty)
}

@Test func aFloatingMemoryGetsNoPhoto() throws {
    let f = try Fixture()
    _ = try f.makeSessionAPhotoSession()
    let span = try #require(try f.store.memories.spans(of: try f.memory("The old house", segment: 1).id).first)
    let floating = try f.store.memories.insertFloating(title: "graduation", segment: span.segmentID, startMs: span.startMs, endMs: span.endMs)
    #expect(try f.links(of: floating.id).isEmpty, "the person did not tell it")
}

@Test func aRemovedPhotoStaysRemovedOnALaterRead() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let kept = try f.actions.acceptMemory(try f.card()).memory
    _ = try f.photos.unlink(subject.id, from: .memory(kept.id))
    #expect(try f.store.memories.memories(in: f.sessionID).map(\.id) == [kept.id])
    #expect(try f.links(of: kept.id).isEmpty, "reading memories does not link the session's photo again")
}

@Test func aFailedKeepLinksNothing() throws {
    let f = try Fixture()
    _ = try f.makeSessionAPhotoSession()
    let card = try f.card()
    let memory = Memory(id: .init(), title: "The tree house", summaryQuote: "the tree", visibility: .timeline, chapterID: nil,
                        createdFromCandidateID: card.id, createdAt: .now, hiddenFromTimeline: false, kind: .event)
    let span = MemorySpan(memoryID: memory.id, segmentID: f.segments[0].id, startMs: 0, endMs: 100, order: 0)
    // Joining a chapter that does not exist fails after the link is written: the link must roll back with the memory.
    #expect(throws: (any Error).self) {
        try f.store.memories.insert(memory, spans: [span], people: [], places: [], anchors: [], acceptingCandidate: card.id,
                                    joiningStory: (id: StoryID(), chapterID: ChapterID(rawValue: "missing")))
    }
    #expect(try f.store.memories.fetch(memory.id) == nil)
    #expect(try f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link") } == 0)
}

@Test func undoingAMergeTakesBackThePhotoItAdded() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let target = try f.memory("The old house", segment: 1)
    let merged = try f.actions.mergeCandidate(try f.card(), into: target.id)
    #expect(try f.links(of: target.id) == ["\(subject.id.rawValue) cover"])
    try f.actions.unmerge(merged.receipt)
    #expect(try f.links(of: target.id).isEmpty)
    #expect(try f.photos.photo(id: subject.id) != nil, "the session still points at it")
    #expect(try f.photos.subjectPhoto(of: f.sessionID)?.id == subject.id)
}

@Test func undoingAMergeKeepsAPhotoTheTargetAlreadyHeld() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let target = try f.memory("The old house", segment: 1), other = photo("other", at: 1)
    try f.photos.insert(other, linkingTo: .memory(target.id))
    try f.photos.link(subject.id, to: .memory(target.id))
    let before = try f.links(of: target.id)
    let merged = try f.actions.mergeCandidate(try f.card(), into: target.id)
    try f.actions.unmerge(merged.receipt)
    #expect(try f.links(of: target.id) == before && before == ["\(other.id.rawValue) cover", "\(subject.id.rawValue) attached"])
}

@Test func undoingAMergeThatTookTheCoverPassesTheCoverOn() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let target = try f.memory("The old house", segment: 1)
    let merged = try f.actions.mergeCandidate(try f.card(), into: target.id)
    let later = photo("later", at: 2)
    try f.photos.insert(later, linkingTo: .memory(target.id))
    #expect(try f.links(of: target.id) == ["\(subject.id.rawValue) cover", "\(later.id.rawValue) attached"])
    try f.actions.unmerge(merged.receipt)
    #expect(try f.links(of: target.id) == ["\(later.id.rawValue) cover"])
}

@Test func undoingAGroupMergeTakesBackThePhotoItAddedAndKeepsAHeldOne() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let first = try f.memory("The old house", segment: 1), second = try f.memory("The old house again", segment: 0)
    let merged = try f.actions.mergeGroup(try f.card(ordinal: 1), into: [first.id, second.id])
    #expect(merged.receipt.addedPhoto == subject.id)
    try f.actions.unmerge(merged.receipt)
    #expect(try f.links(of: merged.receipt.target).isEmpty && (try f.photos.photo(id: subject.id)) != nil)

    let g = try Fixture(), held = try g.makeSessionAPhotoSession()
    let a = try g.memory("The old house", segment: 1), b = try g.memory("The old house again", segment: 0)
    // Either may be the oldest, so both hold it.
    try g.photos.link(held.id, to: .memory(a.id)); try g.photos.link(held.id, to: .memory(b.id))
    let again = try g.actions.mergeGroup(try g.card(ordinal: 1), into: [a.id, b.id])
    #expect(again.receipt.addedPhoto == nil)
    try g.actions.unmerge(again.receipt)
    #expect(try g.links(of: again.receipt.target) == ["\(held.id.rawValue) cover"])
}

@Test func undoingAKeepLeavesNoLinkAndKeepsThePhoto() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let kept = try f.actions.acceptMemory(try f.card()).memory
    try f.store.memories.delete(kept.id)
    #expect(try f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link") } == 0)
    #expect(try f.photos.photo(id: subject.id) != nil)
}

@Test func separatingATellingLeavesThePhotoOnTheOriginal() throws {
    let f = try Fixture(), subject = try f.makeSessionAPhotoSession()
    let target = try f.memory("The old house", segment: 1)
    _ = try f.actions.mergeCandidate(try f.card(), into: target.id)
    let fresh = try f.actions.separateTelling(target.id, order: 1)
    #expect(try f.links(of: fresh.id).isEmpty)
    #expect(try f.links(of: target.id) == ["\(subject.id.rawValue) cover"])
}

@Test func subjectsOfAPhotoListEveryMemoryAndEntityThatHoldsIt() throws {
    let f = try Fixture(), maya = try f.person("Maya"), m = try f.memory("The tree house", segment: 0)
    let shared = photo("shared"), lone = photo("lone")
    try f.photos.insert(shared, linkingTo: .entity(maya.id)); try f.photos.link(shared.id, to: .memory(m.id)); try f.photos.insert(lone)
    let held = try f.photos.subjects(of: shared.id)
    #expect(held.memories == [m.id] && held.entities == [maya.id])
    let none = try f.photos.subjects(of: lone.id)
    #expect(none.memories.isEmpty && none.entities.isEmpty)
}
