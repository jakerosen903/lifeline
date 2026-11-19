import Foundation
import GRDB
import ImageIO
import UniformTypeIdentifiers
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

@Test func anOldCopyThatAMemoryAlsoHoldsSurvivesALinkToAnotherContact() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA), "c-reyes": try f.picture("reyes", rgb: 0xAA6633)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let (_, segments) = try StoreFixtures.session(in: f.store.sessions, segments: ["the fence"])
    let fence = try StoreFixtures.memory(in: f.store.memories, candidates: f.store.candidates, segment: segments[0].id, title: "The fence")
    try await f.actions.link(robin.id, to: vale)
    let oldCopyID = try #require(try f.person(robin.id).contactPhotoID)
    try f.store.photos.link(oldCopyID, to: .memory(fence.id))

    try await f.actions.link(robin.id, to: reyes)
    let newCopy = try #require(try f.person(robin.id).contactPhotoID)
    #expect(try f.photos(of: robin.id).map(\.id) == [newCopy], "the old copy leaves the person")
    let oldCopy = try #require(try f.store.photos.photo(id: oldCopyID), "the memory still holds it")
    #expect(f.file(oldCopy))
    #expect(try f.store.photos.photos(of: .memory(fence.id)).map(\.id) == [oldCopyID])
}

// MARK: - Picture formats

/// A small image in `type` (PNG or HEIC); nil when this host cannot write that type.
private func pictureData(as type: UTType) throws -> Data? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    guard let image = context.makeImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

@Test(arguments: [UTType.png, UTType.heic])
func aPictureInAnyImageFormatIsCopied(_ type: UTType) async throws {
    let f = try Fixture()
    let data = try #require(try pictureData(as: type), "this host cannot write \(type.identifier)")
    f.directory.pictures = ["c-vale": data]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let copy = try #require(try f.person(robin.id).contactPhotoID)
    #expect(try f.photos(of: robin.id).map(\.id) == [copy])
    let stored = try #require(try f.store.photos.photo(id: copy))
    #expect(f.file(stored))
}

// MARK: - One transaction for the copy

private struct InjectedFailure: Error {}

@Test func aFailureBetweenThePhotoAndItsRecordLeavesNothingAndASecondCopyCompletes() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.db.writer.write { db in
        try db.execute(sql: "update person set contact_identifier = 'c-vale', contact_name = 'Robyn Vale', contact_state = 'linked' where id = ?",
                       arguments: [robin.id.rawValue])
    }
    let failing = ContactLinkActions(store: f.store, photos: f.library, directory: f.directory, scratch: f.scratch,
                                     beforeRecord: { throw InjectedFailure() })
    await #expect(throws: InjectedFailure.self) { try await failing.copyPicture(for: robin.id) }
    let rows = try await f.db.writer.read { db in
        [try Int.fetchOne(db, sql: "select count(*) from photo"), try Int.fetchOne(db, sql: "select count(*) from photo_link")]
    }
    #expect(rows == [0, 0], "no photo row and no link")
    #expect(try f.person(robin.id).contactPhotoID == nil)
    let folder = try PhotoLocation.directory(under: f.root)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".jpg") }.isEmpty, "no file")

    try await f.actions.copyPicture(for: robin.id)
    let copy = try #require(try f.person(robin.id).contactPhotoID, "the second copy is recorded as the app's")
    #expect(try f.photos(of: robin.id).map(\.id) == [copy])
}

// MARK: - Unlink

@Test func unlinkKeepsThePersonTheirMomentsNamesAndPicture() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let moment = try f.kept("Robyn painted the fence", people: ["Robyn"])
    let robyn = try f.onlyPerson(moment)
    try await f.actions.copyPicture(for: robyn)
    let made = try f.person(robyn)
    #expect(made.nameOrigin == .contact && made.contactIdentifier == "c-vale" && made.createdByGuess)
    let copy = try #require(made.contactPhotoID)
    let aliases = try f.store.people.aliasesOldestFirst(of: robyn)

    try f.actions.unlink(robyn)
    let unlinked = try f.person(robyn)
    #expect(unlinked.contactIdentifier == nil && unlinked.contactName == nil && unlinked.contactState == nil && unlinked.contactPhotoID == nil)
    #expect(unlinked.displayName == "Robyn Vale" && unlinked.nameOrigin == .contact, "the name stays")
    #expect(!unlinked.createdByGuess, "the owner acted: no longer a guess a move may remove (PB19)")
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

// PC-b Task 6: the picture the app copies after a move to a contact does not make that move's Undo stale (PB12).
@Test func undoOfAMoveToAContactSucceedsAfterThePictureWasCopied() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-reyes": try f.picture("reyes", rgb: 0xAA6633)]
    // No contact fits "my cousin", so Keep makes a person with the said name.
    let memory = try f.kept("my cousin painted the fence", people: ["my cousin"])
    let cousin = try f.onlyPerson(memory)
    let link = try #require(try f.store.personLinks.links(to: cousin).first)
    let receipt = try f.moves.move(link, to: .contact(reyes), wholeGroup: false)
    let made = try #require(receipt.createdPerson)
    try await f.actions.copyPicture(for: made)
    let copy = try #require(try f.person(made).contactPhotoID)
    #expect(try f.photos(of: made).map(\.id) == [copy])

    try f.moves.undo(receipt)
    #expect(try f.store.people.person(id: made) == nil, "Undo removes the person and the copy's link")
    #expect(try f.store.people.person(id: cousin) != nil)
    let links = try await f.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link where photo_id = ?", arguments: [copy.rawValue]) }
    #expect(links == 0)
    #expect(try await f.db.writer.read { try Photo.exists($0, key: copy.rawValue) }, "the homeless row waits for the sweep (PB12)")
}

@Test func undoOfAMoveToAContactIsRefusedOnceTheOwnerAddedAPhoto() async throws {
    let f = try Fixture()
    let memory = try f.kept("my cousin painted the fence", people: ["my cousin"])
    let link = try #require(try f.store.personLinks.links(to: try f.onlyPerson(memory)).first)
    let receipt = try f.moves.move(link, to: .contact(reyes), wholeGroup: false)
    let made = try #require(receipt.createdPerson)
    _ = try await f.library.add(fileAt: try f.source("own", rgb: 0x22AA22), assetLocalID: nil, to: .entity(EntityID(rawValue: made.rawValue)))
    #expect(throws: PersonLinkActions.Error.stale) { try f.moves.undo(receipt) }
    #expect(try f.store.people.person(id: made) != nil, "a photo the owner added keeps the person")
}

// MARK: - The picture after Keep and "Same story" (I-2, fix wave)

@Test func aPersonKeepMakesFromAContactGetsThePictureAfterKeep() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let memory = try f.kept("Robyn painted the fence", people: ["Robyn"])
    let robyn = try f.onlyPerson(memory)
    #expect(try f.person(robyn).contactPhotoID == nil, "Keep's transaction copies no picture")

    #expect(await f.actions.copyMissingPictures(of: memory.id) == [robyn])
    let placed = try f.photos(of: robyn)
    #expect(placed.count == 1 && placed[0].isCover)
    #expect(try f.person(robyn).contactPhotoID == placed[0].id)
    let before = try f.dump()
    #expect(await f.actions.copyMissingPictures(of: memory.id).isEmpty, "a second call copies nothing")
    #expect(try f.dump() == before)
}

@Test func aSameStoryMergeThatNamesAContactGetsThePicture() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-reyes": try f.picture("reyes", rgb: 0x996633)]
    let target = try f.kept("We drove to the coast", people: [])
    let segment = try StoreFixtures.session(in: f.store.sessions, segments: ["Tomas drove us to the coast"]).1[0].id
    let out = MemoryOut(ref: "m0", kind: .event, title: "A title", quote: "Tomas drove us to the coast", segmentSpan: WordSpan(startWord: 0, endWord: 5),
                        peopleRefs: ["Tomas"], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: nil)
    let card = StoreFixtures.candidate(segment, ordinal: 0, payload: try CandidatePayload.encode(out))
    try f.store.candidates.insert(card)
    let merged = try f.keep.mergeCandidate(card, into: target.id)
    let tomas = try f.onlyPerson(target)

    #expect(await f.actions.copyMissingPictures(of: merged.receipt.target) == [tomas])
    #expect(try f.person(tomas).contactPhotoID != nil)
}

@Test func copyMissingPicturesLeavesAPersonWithNoContact() async throws {
    let f = try Fixture(cards: [])
    let memory = try f.kept("Robyn painted the fence", people: ["Robyn"])
    let before = try f.dump()
    #expect(await f.actions.copyMissingPictures(of: memory.id).isEmpty)
    #expect(try f.dump() == before)
}
