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
    var photos: PhotoRepository { store.photos }

    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        (_, segments) = try StoreFixtures.session(in: store.sessions, segments: ["the tree house", "the old house"])
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
