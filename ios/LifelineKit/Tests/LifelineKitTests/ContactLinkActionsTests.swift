import Foundation
import GRDB
import Testing
@testable import LifelineKit

// PC-b Task 3: link a person to a contact, unlink, and copy the contact's picture. Names are invented.

private let vale = ContactCard(identifier: "c-vale", fullName: "Robyn Vale", givenName: "Robyn", familyName: "Vale", nickname: "", hasPicture: true)
private let reyes = ContactCard(identifier: "c-reyes", fullName: "Tomas Reyes", givenName: "Tomas", familyName: "Reyes", nickname: "", hasPicture: true)

private final class Fixture: @unchecked Sendable {
    let root: URL, scratch: URL
    let db: AppDatabase, store: ExtractionStore
    let library: PhotoLibrary
    let directory: ScriptedContactsDirectory
    let actions: ContactLinkActions
    let keep: CandidateActions
    let moves: PersonLinkActions

    init(cards: [ContactCard] = [vale, reyes]) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "contact-link-\(UUID().uuidString)", directoryHint: .isDirectory)
        scratch = root.appending(path: "scratch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        library = PhotoLibrary(root: root, photos: store.photos)
        directory = ScriptedContactsDirectory(cards: cards)
        actions = ContactLinkActions(store: store, photos: library, directory: directory, scratch: scratch)
        var keep = CandidateActions(store: store)
        keep.contactsForGuess = { cards.map(\.forGuess) }
        self.keep = keep
        moves = PersonLinkActions(store: store)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// A generated JPEG's bytes, one colour per picture.
    func picture(_ name: String, rgb: Int) throws -> Data { try Data(contentsOf: try source(name, rgb: rgb)) }

    func source(_ name: String, rgb: Int) throws -> URL {
        let folder = root.appending(path: "sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).jpg")
        if !FileManager.default.fileExists(atPath: url.path) { try GeneratedPhoto.write(to: url, width: 64, height: 64, rgb: rgb) }
        return url
    }

    func person(_ id: PersonID) throws -> Person { try #require(try store.people.person(id: id)) }
    func photos(of person: PersonID) throws -> [PlacedPhoto] { try store.photos.photos(of: .entity(EntityID(rawValue: person.rawValue))) }
    func file(_ photo: Photo) -> Bool { FileManager.default.fileExists(atPath: library.url(for: photo).path) }

    /// A memory kept the way the owner keeps it, so Keep's guess makes the person.
    func kept(_ text: String, people: [String]) throws -> Memory {
        let segment = try StoreFixtures.session(in: store.sessions, segments: [text]).1[0].id
        let out = MemoryOut(ref: "m0", kind: .event, title: "A title", quote: text,
                            segmentSpan: WordSpan(startWord: 0, endWord: text.split(separator: " ").count - 1),
                            peopleRefs: people, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: nil)
        let card = StoreFixtures.candidate(segment, ordinal: 0, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(card)
        return try keep.acceptMemory(card, joinStory: false).memory
    }

    func onlyPerson(_ memory: Memory) throws -> PersonID {
        let rows = try store.entities.links(of: memory.id).filter { $0.entity.type == .person }
        try #require(rows.count == 1)
        return PersonID(rawValue: rows[0].entity.id.rawValue)
    }

    func dump() throws -> [String] {
        try db.writer.read { db in
            var out: [String] = []
            for table in ["person", "entity", "moment_entity", "alias", "photo", "photo_link"] {
                out += try Row.fetchAll(db, sql: "select * from \(table)").map { "\(table): \($0.description)" }.sorted()
            }
            return out
        }
    }
}

// MARK: - Link

@Test func linkSetsTheContactFieldsAndKeepsTheName() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.db.writer.write { db in
        try db.execute(sql: "update person set name_origin = 'said', created_by_guess = 1 where id = ?", arguments: [robin.id.rawValue])
    }
    try await f.actions.link(robin.id, to: vale)
    let linked = try f.person(robin.id)
    #expect(linked.contactIdentifier == "c-vale" && linked.contactName == "Robyn Vale" && linked.contactState == "linked")
    #expect(linked.displayName == "Robin" && linked.nameOrigin == .said, "a person on file keeps their name")
    #expect(!linked.createdByGuess, "the owner acted (PB3)")
    #expect(try f.store.people.aliases(of: robin.id).map(\.text) == ["Robin"], "the contact's name is never an alias")
    #expect(try f.photos(of: robin.id).isEmpty && linked.contactPhotoID == nil, "a contact with no picture adds nothing")
    #expect(try f.store.people.person(holding: "c-vale")?.id == robin.id)
    #expect(try f.store.people.linkedPersons().map(\.id) == [robin.id])
}

@Test func theAppsOwnLinkLeavesTheGuessFlag() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.db.writer.write { db in
        try db.execute(sql: "update person set name_origin = 'said', created_by_guess = 1 where id = ?", arguments: [robin.id.rawValue])
    }
    try await f.actions.link(robin.id, to: vale, clearingGuess: false)
    let linked = try f.person(robin.id)
    #expect(linked.createdByGuess && linked.contactIdentifier == "c-vale")
}

@Test func aPersonWithNoPhotoGetsThePictureAsTheirKeyPhoto() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let placed = try f.photos(of: robin.id)
    #expect(placed.count == 1 && placed[0].isCover)
    #expect(try f.person(robin.id).contactPhotoID == placed[0].id)
    #expect(f.file(placed[0].photo))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.scratch.path).isEmpty, "the temporary folder is gone")
}

@Test func aPersonWithTwoPhotosGetsThePictureThird() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let one = try await f.library.add(fileAt: try f.source("one", rgb: 0xAA2222), assetLocalID: nil, to: .entity(robin.entityID))
    let two = try await f.library.add(fileAt: try f.source("two", rgb: 0x22AA22), assetLocalID: nil, to: .entity(robin.entityID))
    try await f.actions.link(robin.id, to: vale)
    let placed = try f.photos(of: robin.id)
    let copy = try #require(try f.person(robin.id).contactPhotoID)
    #expect(placed.map(\.id) == [one.id, two.id, copy])
    #expect(placed.map(\.isCover) == [true, false, false], "the key photo stays")
}

@Test func aPictureThatIsAlreadyTheOwnersPhotoIsNotRecordedAsTheCopy() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let own = try await f.library.add(fileAt: try f.source("vale", rgb: 0x3366AA), assetLocalID: nil, to: .entity(robin.entityID))
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    try await f.actions.link(robin.id, to: vale)
    #expect(try f.photos(of: robin.id).map(\.id) == [own.id], "nothing new")
    #expect(try f.person(robin.id).contactPhotoID == nil)
}

@Test func aContactHeldByAnotherPersonIsRefusedWithTheirName() async throws {
    let f = try Fixture()
    let robyn = try f.store.people.insertPerson(displayName: "Robyn")
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robyn.id, to: vale)
    let before = try f.dump()
    await #expect(throws: ContactLinkActions.Error.heldByAnother(robyn.id, name: "Robyn")) { try await f.actions.link(robin.id, to: vale) }
    #expect(try f.dump() == before, "no row changes")
}

@Test func aLinkOfAMissingPersonIsNotFound() async throws {
    let f = try Fixture()
    await #expect(throws: ContactLinkActions.Error.notFound) { try await f.actions.link(PersonID(), to: vale) }
    #expect(throws: ContactLinkActions.Error.notFound) { try f.actions.unlink(PersonID()) }
}

@Test func linkingTheSameContactAgainKeepsTheCopy() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let before = try f.dump()
    try await f.actions.link(robin.id, to: vale)
    #expect(try f.dump() == before)
}

@Test func aSecondContactReplacesTheFirstAndItsCopiedPicture() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA), "c-reyes": try f.picture("reyes", rgb: 0xAA6633)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let own = try await f.library.add(fileAt: try f.source("own", rgb: 0x22AA22), assetLocalID: nil, to: .entity(robin.entityID))
    try await f.actions.link(robin.id, to: vale)
    let oldCopyID = try #require(try f.person(robin.id).contactPhotoID)
    let oldCopy = try #require(try f.store.photos.photo(id: oldCopyID))

    try await f.actions.link(robin.id, to: reyes)
    let linked = try f.person(robin.id)
    #expect(linked.contactIdentifier == "c-reyes" && linked.contactName == "Tomas Reyes" && linked.contactState == "linked")
    let newCopy = try #require(linked.contactPhotoID)
    #expect(try f.photos(of: robin.id).map(\.id) == [own.id, newCopy], "the owner's photo stays; the old copy goes")
    #expect(try f.store.photos.photo(id: oldCopy.id) == nil && !f.file(oldCopy))
}

@Test func aSecondContactLeavesAPictureThatWasNeverTheAppsCopy() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let own = try await f.library.add(fileAt: try f.source("vale", rgb: 0x3366AA), assetLocalID: nil, to: .entity(robin.entityID))
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA), "c-reyes": try f.picture("reyes", rgb: 0xAA6633)]
    try await f.actions.link(robin.id, to: vale)
    try await f.actions.link(robin.id, to: reyes)
    let copy = try #require(try f.person(robin.id).contactPhotoID)
    #expect(try f.photos(of: robin.id).map(\.id) == [own.id, copy])
}

@Test func aPictureThatCannotBeReadDoesNotUndoTheLink() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    f.directory.failsOnRead = true
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    #expect(try f.person(robin.id).contactIdentifier == "c-vale")
    #expect(try f.photos(of: robin.id).isEmpty)
    f.directory.failsOnRead = false
    try await f.actions.copyPicture(for: robin.id)
    #expect(try f.photos(of: robin.id).count == 1, "a later copy fills it in")
    #expect(try f.person(robin.id).contactPhotoID != nil)
}

// MARK: - The copy, twice and after a kill

@Test func copyPictureIsSafeToCallAgain() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    // A kill after the link's transaction and before the copy: the fields, and no picture yet.
    try await f.db.writer.write { db in
        try db.execute(sql: "update person set contact_identifier = 'c-vale', contact_name = 'Robyn Vale', contact_state = 'linked' where id = ?",
                       arguments: [robin.id.rawValue])
    }
    try await f.actions.copyPicture(for: robin.id)
    let after = try f.dump()
    try await f.actions.copyPicture(for: robin.id)
    #expect(try f.dump() == after, "a copy is made once")
    #expect(try f.photos(of: robin.id).count == 1)

    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    let unlinked = try f.dump()
    try await f.actions.copyPicture(for: tomas.id)
    #expect(try f.dump() == unlinked, "no contact, nothing to copy")
}

// MARK: - Unlink

@Test func unlinkKeepsThePersonTheirMomentsNamesAndPicture() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let moment = try f.kept("Robyn painted the fence", people: ["Robyn"])
    let robyn = try f.onlyPerson(moment)
    try await f.actions.copyPicture(for: robyn)
    let made = try f.person(robyn)
    #expect(made.nameOrigin == .contact && made.contactIdentifier == "c-vale")
    let copy = try #require(made.contactPhotoID)
    let aliases = try f.store.people.aliasesOldestFirst(of: robyn)

    try f.actions.unlink(robyn)
    let unlinked = try f.person(robyn)
    #expect(unlinked.contactIdentifier == nil && unlinked.contactName == nil && unlinked.contactState == nil && unlinked.contactPhotoID == nil)
    #expect(unlinked.displayName == "Robyn Vale" && unlinked.nameOrigin == .contact, "the name stays")
    #expect(try f.photos(of: robyn).map(\.id) == [copy], "the picture stays as an ordinary photo")
    #expect(try f.store.people.aliasesOldestFirst(of: robyn) == aliases)
    #expect(try f.onlyPerson(moment) == robyn)
    #expect(try f.store.people.linkedPersons().isEmpty)
    #expect(try f.store.people.person(holding: "c-vale") == nil)
}

@Test func unlinkOfAPersonWithNoContactDoesNothing() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let before = try f.dump()
    try f.actions.unlink(robin.id)
    #expect(try f.dump() == before)
}

// MARK: - PB12: the copied picture does not keep a person the app made from a guess

@Test func aMoveRemovesAGuessFromAContactWithItsCopiedPictureAndUndoRestoresBoth() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let moment = try f.kept("Robyn painted the fence", people: ["Robyn"])
    let robyn = try f.onlyPerson(moment)
    try await f.actions.copyPicture(for: robyn)
    let copy = try #require(try f.person(robyn).contactPhotoID)
    #expect(try f.person(robyn).createdByGuess, "the copy is the app's act, not the owner's")
    let before = try f.dump()

    let link = try #require(try f.store.personLinks.links(to: robyn).first { $0.memoryID == moment.id })
    let receipt = try f.moves.move(link, to: .person(robin.id), wholeGroup: false)
    #expect(receipt.removedPerson?.id == robyn)
    #expect(try f.store.people.person(id: robyn) == nil)
    #expect(try f.store.photos.photo(id: copy) != nil, "the homeless row waits for the sweep")

    try f.moves.undo(receipt)
    #expect(try f.dump() == before, "the person, contact_photo_id and the photo link as they were")
    #expect(try f.person(robyn).contactPhotoID == copy)
    #expect(try f.photos(of: robyn).map(\.id) == [copy])
}

@Test func undoAfterASweepTookTheCopyRestoresThePersonWithoutIt() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let moment = try f.kept("Robyn painted the fence", people: ["Robyn"])
    let robyn = try f.onlyPerson(moment)
    try await f.actions.copyPicture(for: robyn)
    let link = try #require(try f.store.personLinks.links(to: robyn).first { $0.memoryID == moment.id })
    let receipt = try f.moves.move(link, to: .person(robin.id), wholeGroup: false)
    try await f.library.sweep()

    try f.moves.undo(receipt)
    let back = try f.person(robyn)
    #expect(back.contactIdentifier == "c-vale" && back.contactPhotoID == nil)
    #expect(try f.photos(of: robyn).isEmpty)
}

@Test func aPhotoTheOwnerAddedKeepsAGuessFromAContact() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let moment = try f.kept("Robyn painted the fence", people: ["Robyn"])
    let robyn = try f.onlyPerson(moment)
    try await f.actions.copyPicture(for: robyn)
    _ = try await f.library.add(fileAt: try f.source("own", rgb: 0x22AA22), assetLocalID: nil, to: .entity(EntityID(rawValue: robyn.rawValue)))

    let link = try #require(try f.store.personLinks.links(to: robyn).first { $0.memoryID == moment.id })
    #expect(try f.moves.move(link, to: .person(robin.id), wholeGroup: false).removedPerson == nil)
    #expect(try f.store.people.person(id: robyn) != nil)
}
