import Foundation
import GRDB
import Testing
@testable import LifelineKit

// PC-b Task 4: the check of linked contacts, a contact that changes, and the look again after access
// (`reguess`). Names are invented.

private let vale = ContactCard(identifier: "c-vale", fullName: "Robyn Vale", givenName: "Robyn", familyName: "Vale", nickname: "", hasPicture: true)
private let reyes = ContactCard(identifier: "c-reyes", fullName: "Tomas Reyes", givenName: "Tomas", familyName: "Reyes", nickname: "", hasPicture: true)

private func card(_ identifier: String, _ given: String, _ family: String) -> ContactCard {
    ContactCard(identifier: identifier, fullName: "\(given) \(family)", givenName: given, familyName: family, nickname: "", hasPicture: true)
}

private final class Fixture: @unchecked Sendable {
    let root: URL, scratch: URL
    let db: AppDatabase, store: ExtractionStore
    let library: PhotoLibrary
    let directory: ScriptedContactsDirectory
    let actions: ContactLinkActions
    let keep: CandidateActions

    /// `keepContacts` is what Keep's guess sees; `cards` is what the directory holds.
    init(cards: [ContactCard] = [vale, reyes], keepContacts: [ContactCard] = []) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "contact-check-\(UUID().uuidString)", directoryHint: .isDirectory)
        scratch = root.appending(path: "scratch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        library = PhotoLibrary(root: root, photos: store.photos)
        directory = ScriptedContactsDirectory(cards: cards)
        actions = ContactLinkActions(store: store, photos: library, directory: directory, scratch: scratch)
        var keep = CandidateActions(store: store)
        keep.contactsForGuess = { keepContacts.map(\.forGuess) }
        self.keep = keep
    }

    deinit { try? FileManager.default.removeItem(at: root) }

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
    /// Rows changed on the one connection since it opened: a check that writes nothing leaves it as it was.
    func changes() throws -> Int { try db.writer.read { $0.totalChangesCount } }
    func photoRows() throws -> Int { try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo") ?? 0 } }

    func setNameOrigin(_ origin: NameOrigin, _ id: PersonID, guess: Bool = false) async throws {
        try await db.writer.write { db in
            try db.execute(sql: "update person set name_origin = ?, created_by_guess = ? where id = ?",
                           arguments: [origin.rawValue, guess, id.rawValue])
        }
    }

    /// One recording; each text is a segment kept as one memory naming `people`.
    func keptSession(_ texts: [(text: String, people: [String])]) throws -> (SessionID, [Memory]) {
        let (session, segments) = try StoreFixtures.session(in: store.sessions, segments: texts.map(\.text))
        var memories: [Memory] = []
        for (i, item) in texts.enumerated() {
            let out = MemoryOut(ref: "m\(i)", kind: .event, title: "A title", quote: item.text,
                                segmentSpan: WordSpan(startWord: 0, endWord: item.text.split(separator: " ").count - 1),
                                peopleRefs: item.people, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil,
                                confidence: 0.9, aboutRef: nil)
            let candidate = StoreFixtures.candidate(segments[i].id, ordinal: 0, payload: try CandidatePayload.encode(out))
            try store.candidates.insert(candidate)
            memories.append(try keep.acceptMemory(candidate, joinStory: false).memory)
        }
        return (session, memories)
    }

    func onlyPerson(_ memory: Memory) throws -> PersonID {
        let rows = try store.entities.links(of: memory.id).filter { $0.entity.type == .person }
        try #require(rows.count == 1)
        return PersonID(rawValue: rows[0].entity.id.rawValue)
    }

    func origins(of memory: Memory) throws -> [LinkOrigin?] { try store.personLinks.links(of: memory.id).map(\.origin) }

    func dump() throws -> [String] {
        try db.writer.read { db in
            var out: [String] = []
            for table in ["person", "entity", "moment_entity", "alias", "photo", "photo_link", "contact_declined"] {
                out += try Row.fetchAll(db, sql: "select * from \(table)").map { "\(table): \($0.description)" }.sorted()
            }
            return out
        }
    }
}

// MARK: - The scripted directory under each access

@Test func theScriptedDirectoryAnswersNothingWithoutAccess() async throws {
    for access in [ContactsAccess.notAsked, .denied] {
        let directory = ScriptedContactsDirectory(cards: [vale], pictures: ["c-vale": Data([1, 2, 3])], access: access)
        #expect(try await directory.cards(identifiers: ["c-vale"]).isEmpty)
        #expect(try await directory.picture(identifier: "c-vale") == nil)
    }
    let limited = ScriptedContactsDirectory(cards: [vale], pictures: ["c-vale": Data([1, 2, 3])], access: .limited)
    #expect(try await limited.cards(identifiers: ["c-vale"]) == [vale])
    #expect(try await limited.picture(identifier: "c-vale") == Data([1, 2, 3]))
}

@Test func theScriptedDirectoryAnswersAMergedIdentifierWithTheCardThatHoldsItNow() async throws {
    let merged = card("c-merged", "Robyn", "Vale")
    let directory = ScriptedContactsDirectory(cards: [merged, reyes], pictures: ["c-merged": Data([9])])
    directory.merged = ["c-vale": "c-merged"]
    #expect(try await directory.cards(identifiers: ["c-vale", "c-reyes"]) == [merged, reyes])
    #expect(try await directory.cards(identifiers: ["c-vale", "c-merged"]) == [merged], "one card once")
    #expect(try await directory.picture(identifier: "c-vale") == Data([9]))
}

// MARK: - Renamed

@Test func aRenamedContactChangesTheKeptNameAndOnlyTheNameThatCameFromIt() async throws {
    let f = try Fixture(keepContacts: [vale])
    let fromContact = try f.onlyPerson(try f.keptSession([("Robyn painted the fence", ["Robyn"])]).1[0])
    #expect(try f.person(fromContact).nameOrigin == .contact && f.person(fromContact).displayName == "Robyn Vale")
    let said = try f.store.people.insertPerson(displayName: "Tom")
    try await f.setNameOrigin(.said, said.id)
    try await f.actions.link(said.id, to: reyes)
    let ines = card("c-ines", "Ines", "Moreau")
    let typed = try f.store.people.insertPerson(displayName: "Auntie Ines")
    try await f.setNameOrigin(.typed, typed.id)
    f.directory.cards = [vale, reyes, ines]
    try await f.actions.link(typed.id, to: ines)
    let aliasesBefore = try [fromContact, said.id, typed.id].map { try f.store.people.aliases(of: $0).map(\.text) }

    f.directory.cards = [card("c-vale", "Robyn", "Vale-Ortiz"), card("c-reyes", "Tomas", "Reyes Jr"), card("c-ines", "Ines", "Laurent")]
    try await f.actions.check()

    let a = try f.person(fromContact), b = try f.person(said.id), c = try f.person(typed.id)
    #expect(a.contactName == "Robyn Vale-Ortiz" && a.displayName == "Robyn Vale-Ortiz" && a.nameOrigin == .contact)
    #expect(b.contactName == "Tomas Reyes Jr" && b.displayName == "Tom" && b.nameOrigin == .said, "a said name stays")
    #expect(c.contactName == "Ines Laurent" && c.displayName == "Auntie Ines" && c.nameOrigin == .typed, "a typed name stays")
    #expect([a, b, c].allSatisfy { $0.contactState == "linked" })
    let aliasesAfter = try [fromContact, said.id, typed.id].map { try f.store.people.aliases(of: $0).map(\.text) }
    #expect(aliasesAfter == aliasesBefore, "a contact's name never becomes an alias (PB10)")
    #expect(f.directory.allReads == 0, "nothing is missing, so all contacts are never read")
}

// MARK: - The picture

@Test func aNewPictureReplacesTheCopyWhileItIsTheFirstPhoto() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let oldCopy = try #require(try f.photos(of: robin.id).first)
    let own = try await f.library.add(fileAt: try f.source("own", rgb: 0xAA2222), assetLocalID: nil, to: .entity(robin.entityID))
    #expect(try f.photos(of: robin.id).map(\.id) == [oldCopy.id, own.id])

    f.directory.pictures = ["c-vale": try f.picture("new", rgb: 0x22AA22)]
    try await f.actions.check()

    let placed = try f.photos(of: robin.id)
    let newCopy = try #require(try f.person(robin.id).contactPhotoID)
    #expect(newCopy != oldCopy.id)
    #expect(placed.map(\.id) == [newCopy, own.id], "the new picture is first; the owner's photo stays")
    #expect(placed[0].isCover)
    #expect(try f.store.photos.photo(id: oldCopy.id) == nil && !f.file(oldCopy.photo), "the old copy is gone")
    #expect(f.file(placed[0].photo))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.scratch.path).isEmpty, "the temporary folder is gone")

    let after = try f.dump()
    try await f.actions.check()
    #expect(try f.dump() == after, "a second check finds the same picture")
}

@Test func anOldCopyThatAMemoryAlsoHoldsKeepsItsRowWhenThePictureChanges() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let oldCopy = try #require(try f.person(robin.id).contactPhotoID)
    let (_, memories) = try f.keptSession([("the fence was blue", [])])
    try f.store.photos.link(oldCopy, to: .memory(memories[0].id))

    f.directory.pictures = ["c-vale": try f.picture("new", rgb: 0x22AA22)]
    try await f.actions.check()

    #expect(try f.person(robin.id).contactPhotoID != oldCopy)
    #expect(try f.photos(of: robin.id).count == 1, "the old copy left the person's page")
    #expect(try f.store.photos.photos(of: .memory(memories[0].id)).map(\.id) == [oldCopy], "the memory keeps it")
}

@Test func aNewPictureChangesNothingWhileTheOwnersPhotoIsFirst() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    _ = try await f.library.add(fileAt: try f.source("own", rgb: 0xAA2222), assetLocalID: nil, to: .entity(robin.entityID))
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    try await f.actions.link(robin.id, to: vale)
    #expect(try f.person(robin.id).contactPhotoID != nil)
    let before = try f.dump()

    f.directory.pictures = ["c-vale": try f.picture("new", rgb: 0x22AA22)]
    try await f.actions.check()

    #expect(try f.dump() == before)
    #expect(try f.photoRows() == 2)
}

@Test func theSamePictureChangesNothing() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let before = try f.dump()
    try await f.actions.check()
    try await f.actions.check()
    #expect(try f.dump() == before)
}

@Test func aCheckWithNothingChangedWritesNothing() async throws {
    let f = try Fixture(keepContacts: [vale])
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    _ = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    try await f.actions.link(tomas.id, to: reyes)
    try await f.actions.check()   // copies the picture of the person Keep made
    let changes = try f.changes()
    try await f.actions.check()
    #expect(try f.changes() == changes)
    f.directory.cards = [reyes]
    try await f.actions.check()   // Robyn Vale is missing now
    let afterMissing = try f.changes()
    try await f.actions.check()
    #expect(try f.changes() == afterMissing, "a person already missing is not written again")
}

@Test func theKeptContactNameIsTrimmed() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: card("c-vale", " Robyn", "Vale "))
    #expect(try f.person(robin.id).contactName == "Robyn Vale")
    f.directory.cards = [card("c-vale", "  Robyn", "Vale-Ortiz  "), reyes]
    try await f.actions.check()
    #expect(try f.person(robin.id).contactName == "Robyn Vale-Ortiz")
}

@Test func aNewPictureThatIsAlreadyAnotherStoredPhotoChangesNothing() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let (_, memories) = try f.keptSession([("the fence was blue", [])])
    _ = try await f.library.add(fileAt: try f.source("owners", rgb: 0x22AA22), assetLocalID: nil, to: .memory(memories[0].id))
    let before = try f.dump()

    f.directory.pictures = ["c-vale": try f.picture("owners", rgb: 0x22AA22)]
    try await f.actions.check()

    #expect(try f.dump() == before, "the app never claims the owner's photo as its copy")
}

// A kill or a change inside the replacement leaves the old copy recorded: never the old copy gone and the new one not recorded.
@Test func aReplacementWhoseCopyIsNoLongerFirstRollsBackWhole() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let copy = try #require(try f.person(robin.id).contactPhotoID)
    let own = try await f.library.add(fileAt: try f.source("own", rgb: 0xAA2222), assetLocalID: nil, to: .entity(robin.entityID))
    try f.store.photos.setCover(own.id, of: .entity(robin.entityID))   // the owner's photo is first now
    let before = try f.dump()

    let id = robin.id
    await #expect(throws: PeopleRepository.ContactChangedDuringCopy.self) {
        _ = try await f.library.addRecordingNew(fileAt: try f.source("new", rgb: 0x22AA22), to: .entity(robin.entityID)) { db, new in
            _ = try PeopleRepository.replaceContactPhoto(copy, with: new, for: id, identifier: "c-vale", in: db)
        }
    }
    #expect(try f.dump() == before, "the new photo rolled back and the old copy is still recorded")
}

@Test func aContactWhosePictureWasRemovedKeepsTheCopy() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("old", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let before = try f.dump()
    f.directory.pictures = [:]
    try await f.actions.check()
    #expect(try f.dump() == before)
}

// Review Focus 3: a picture that failed at the link, or a kill between its file and its row.
@Test func aLinkedPersonWithNoCopyGetsThePictureAtTheNextCheck() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    f.directory.failsOnRead = true
    try await f.actions.link(robin.id, to: vale)
    f.directory.failsOnRead = false
    #expect(try f.person(robin.id).contactPhotoID == nil)

    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    try await f.actions.check()

    let placed = try f.photos(of: robin.id)
    #expect(placed.count == 1 && placed[0].isCover)
    #expect(try f.person(robin.id).contactPhotoID == placed[0].id)
}

@Test func aPictureThatIsTheOwnersPhotoIsAQuietNoOpAtEveryCheck() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    let own = try await f.library.add(fileAt: try f.source("vale", rgb: 0x3366AA), assetLocalID: nil, to: .entity(robin.entityID))
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    try await f.actions.link(robin.id, to: vale)
    let before = try f.dump()
    try await f.actions.check()
    try await f.actions.check()
    #expect(try f.dump() == before)
    #expect(try f.person(robin.id).contactPhotoID == nil && f.photos(of: robin.id).map(\.id) == [own.id])
}

// MARK: - Missing

@Test func anIdentifierThatDoesNotResolveIsLinkedAgainToTheOneContactWithTheKeptName() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let copy = try f.person(robin.id).contactPhotoID

    // A restore on a new phone: the same contact has another identifier, and the same picture.
    let restored = ContactCard(identifier: "c-vale-new", fullName: "robyn  vale", givenName: "Robyn", familyName: "Vale", nickname: "", hasPicture: true)
    f.directory.cards = [restored, reyes]
    f.directory.pictures = ["c-vale-new": try f.picture("vale", rgb: 0x3366AA)]
    try await f.actions.check()

    let linked = try f.person(robin.id)
    #expect(linked.contactIdentifier == "c-vale-new" && linked.contactState == "linked" && linked.contactName == "robyn  vale")
    #expect(linked.contactPhotoID == copy && copy != nil, "the same picture stays the copy")
    #expect(f.directory.allReads == 1)
}

// PB34: under full access the re-link is silent; a different picture then follows the "new picture" rule.
@Test func aReLinkByNameUnderFullAccessReplacesTheCopyWhenThePictureDiffers() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let oldCopy = try #require(try f.person(robin.id).contactPhotoID)

    f.directory.cards = [card("c-vale-new", "Robyn", "Vale"), reyes]
    f.directory.pictures = ["c-vale-new": try f.picture("other", rgb: 0x22AA22)]
    try await f.actions.check()

    let linked = try f.person(robin.id)
    #expect(linked.contactIdentifier == "c-vale-new" && linked.contactState == "linked")
    let newCopy = try #require(linked.contactPhotoID)
    #expect(try newCopy != oldCopy && f.photos(of: robin.id).map(\.id) == [newCopy])
    #expect(try f.store.photos.photo(id: oldCopy) == nil)
}

// PB34: under limited access a contact that is no longer shared is missing, even when a shared namesake fits.
@Test func underLimitedAccessAMissingContactIsNotReLinkedByName() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let copy = try #require(try f.person(robin.id).contactPhotoID)
    let before = try f.dump()

    f.directory.currentAccess = .limited
    f.directory.cards = [card("c-namesake", "Robyn", "Vale"), reyes]
    f.directory.pictures = ["c-namesake": try f.picture("namesake", rgb: 0x22AA22)]
    try await f.actions.check()

    let person = try f.person(robin.id)
    #expect(person.contactState == "missing")
    #expect(person.contactIdentifier == "c-vale" && person.contactName == "Robyn Vale" && person.contactPhotoID == copy)
    #expect(try f.photos(of: robin.id).map(\.id) == [copy], "the app's copy stays the first photo")
    let changed = try f.dump().filter { !before.contains($0) }
    #expect(changed.count == 1 && changed[0].contains("missing"), "only the state changes")
    #expect(f.directory.allReads == 0, "no name match, so all contacts are not read")
}

@Test(arguments: [0, 2])
func anIdentifierThatDoesNotResolveWithNoneOrTwoNameMatchesIsMissing(matches: Int) async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let before = try f.dump()

    f.directory.cards = [reyes] + (0..<matches).map { card("c-other-\($0)", "Robyn", "Vale") }
    try await f.actions.check()

    let person = try f.person(robin.id)
    #expect(person.contactState == "missing")
    #expect(person.contactIdentifier == "c-vale" && person.contactName == "Robyn Vale" && person.contactPhotoID != nil)
    let changed = try f.dump().filter { !before.contains($0) }
    #expect(changed.count == 1 && changed[0].hasPrefix("person:") && changed[0].contains("missing"), "only the state changes")

    try await f.actions.check()
    #expect(try f.person(robin.id).contactState == "missing", "a second check changes nothing more")
}

@Test func aNameMatchHeldByAnotherPersonIsNotTaken() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let twin = card("c-twin", "Robyn", "Vale")
    let other = try f.store.people.insertPerson(displayName: "Robyn the younger")
    f.directory.cards = [twin, reyes]
    try await f.actions.link(other.id, to: twin)

    try await f.actions.check()

    #expect(try f.person(robin.id).contactState == "missing" && f.person(robin.id).contactIdentifier == "c-vale")
    #expect(try f.person(other.id).contactIdentifier == "c-twin")
}

@Test func aMissingContactThatResolvesAgainIsLinked() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    f.directory.cards = [reyes]
    try await f.actions.check()
    #expect(try f.person(robin.id).contactState == "missing")

    f.directory.cards = [vale, reyes]
    try await f.actions.check()
    #expect(try f.person(robin.id).contactState == "linked" && f.person(robin.id).contactIdentifier == "c-vale")
}

@Test func aContactTheSystemMergedKeepsTheIdentifierTheSystemReturns() async throws {
    let f = try Fixture()
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let merged = card("c-merged", "Robyn", "Vale")
    f.directory.cards = [merged, reyes]
    f.directory.merged = ["c-vale": "c-merged"]

    try await f.actions.check()

    let person = try f.person(robin.id)
    #expect(person.contactIdentifier == "c-merged" && person.contactState == "linked")
    #expect(f.directory.allReads == 0, "a merged card is not missing")
}

// Review Focus 4.
@Test(arguments: [ContactsAccess.denied, .notAsked])
func withoutAccessTheCheckChangesNothing(access: ContactsAccess) async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let robin = try f.store.people.insertPerson(displayName: "Robin")
    try await f.actions.link(robin.id, to: vale)
    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    f.directory.pictures = [:]
    try await f.actions.link(tomas.id, to: reyes)
    let before = try f.dump()

    f.directory.currentAccess = access
    f.directory.pictures = ["c-reyes": try f.picture("reyes", rgb: 0x22AA22)]
    try await f.actions.check()

    #expect(try f.dump() == before, "nothing is missing, unlinked or copied")
    #expect(f.directory.allReads == 0)
}

@Test func aCheckWithNoLinkedPersonReadsNothing() async throws {
    let f = try Fixture()
    _ = try f.store.people.insertPerson(displayName: "Robin")
    f.directory.failsOnRead = true
    try await f.actions.check()
}

// MARK: - Reguess (plan decision 7)

@Test func reguessLinksAPersonTheAppMadeToTheOneContactThatFits() async throws {
    let f = try Fixture()
    f.directory.pictures = ["c-vale": try f.picture("vale", rgb: 0x3366AA)]
    let (session, memories) = try f.keptSession([("Robyn painted the fence", ["Robyn"]), ("Robyn fixed the gate", ["Robyn"])])
    let robyn = try f.onlyPerson(memories[0])
    #expect(try f.onlyPerson(memories[1]) == robyn)
    let made = try f.person(robyn)
    #expect(made.nameOrigin == .said && made.createdByGuess && made.contactIdentifier == nil)
    #expect(try f.origins(of: memories[0]) == [.new])
    #expect(try f.origins(of: memories[1]) == [.assumed], "rule 4 on the second card")
    // Both links new, so the test sees every link of the person follow.
    try await f.db.writer.write { db in
        try db.execute(sql: "update moment_entity set origin = 'new' where memory_id = ?", arguments: [memories[1].id.rawValue])
    }

    let result = try await f.actions.reguess(session: session, contacts: [vale.forGuess, reyes.forGuess])

    let linked = try f.person(robyn)
    #expect(linked.contactIdentifier == "c-vale" && linked.contactName == "Robyn Vale" && linked.contactState == "linked")
    #expect(linked.displayName == "Robyn Vale" && linked.nameOrigin == .contact)
    #expect(linked.createdByGuess, "the app acted, so the person is still a guess (PB3)")
    #expect(try f.store.people.aliases(of: robyn).map(\.text) == ["Robyn"], "the said name stays; the contact's name is not an alias")
    #expect(try f.store.people.nameForModel(of: robyn) == "Robyn")
    #expect(try f.origins(of: memories[0]) == [.assumed] && f.origins(of: memories[1]) == [.assumed])
    #expect(result.changedLinks == 2)
    #expect(result.linkedPeople == [robyn], "the caller copies the pictures of these people")
    #expect(linked.contactPhotoID == nil, "the caller copies the picture")
}

@Test func reguessCountsEachLinkItChanged() async throws {
    let f = try Fixture()
    let (session, _) = try f.keptSession([("Robyn painted the fence", ["Robyn"]), ("Tomas fixed the gate", ["Tomas"])])
    #expect(try await f.actions.reguess(session: session, contacts: [vale.forGuess, reyes.forGuess]).changedLinks == 2)
    #expect(try await f.actions.reguess(session: session, contacts: [vale.forGuess, reyes.forGuess]).changedLinks == 0, "a second run finds nothing")
}

@Test func reguessLeavesAPersonTheOwnerRenamed() async throws {
    let f = try Fixture()
    let (session, memories) = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    let robyn = try f.onlyPerson(memories[0])
    try f.store.people.rename(robyn, to: "Robyn from next door")
    let before = try f.dump()
    #expect(try await f.actions.reguess(session: session, contacts: [vale.forGuess]).changedLinks == 0)
    #expect(try f.dump() == before)
}

@Test func reguessLeavesALinkInAnotherSession() async throws {
    let f = try Fixture()
    let (first, _) = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    let (_, later) = try f.keptSession([("Tomas fixed the gate", ["Tomas"])])
    let tomas = try f.onlyPerson(later[0])
    #expect(try await f.actions.reguess(session: first, contacts: [vale.forGuess, reyes.forGuess]).changedLinks == 1)
    #expect(try f.person(tomas).contactIdentifier == nil && f.person(tomas).displayName == "Tomas")
    #expect(try f.origins(of: later[0]) == [.new])
}

@Test func reguessLeavesAnAssumedLinkToAPersonOnFile() async throws {
    let f = try Fixture()
    _ = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    let (later, memories) = try f.keptSession([("Robyn fixed the gate", ["Robyn"])])
    #expect(try f.origins(of: memories[0]) == [.assumed], "rule 4")
    let before = try f.dump()
    #expect(try await f.actions.reguess(session: later, contacts: [vale.forGuess]).changedLinks == 0)
    #expect(try f.dump() == before)
}

@Test func reguessLeavesAPersonWhenTwoContactsFit() async throws {
    let f = try Fixture()
    let (session, _) = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    let before = try f.dump()
    let twin = card("c-twin", "Robyn", "Okafor")
    #expect(try await f.actions.reguess(session: session, contacts: [vale.forGuess, twin.forGuess]).changedLinks == 0)
    #expect(try f.dump() == before)
}

@Test func reguessLeavesAContactTheOwnerDeclinedForThatPerson() async throws {
    let f = try Fixture()
    let (session, memories) = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    let robyn = try f.onlyPerson(memories[0])
    try f.actions.decline(vale, for: robyn)
    let before = try f.dump()
    let result = try await f.actions.reguess(session: session, contacts: [vale.forGuess])
    #expect(result.changedLinks == 0 && result.linkedPeople.isEmpty)
    #expect(try f.dump() == before)
}

@Test func reguessLeavesAContactAnotherPersonHolds() async throws {
    let f = try Fixture()
    let holder = try f.store.people.insertPerson(displayName: "Bobbie")
    try await f.actions.link(holder.id, to: vale)
    let (session, _) = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    #expect(try await f.actions.reguess(session: session, contacts: [vale.forGuess]).changedLinks == 0)
}

// MARK: - A picture the owner removed (I-3, fix wave)

extension Fixture {
    /// Robin linked to Robyn Vale, with the app's copy of her picture. Returns the copy.
    func robinWithTheCopy() async throws -> (PersonID, PhotoID) {
        directory.pictures = ["c-vale": try picture("vale", rgb: 0x3366AA), "c-reyes": try picture("reyes", rgb: 0x996633)]
        let robin = try store.people.insertPerson(displayName: "Robin")
        try await actions.link(robin.id, to: vale)
        return (robin.id, try #require(try person(robin.id).contactPhotoID))
    }

    /// The owner removes the copy from the page, as the page does it.
    func ownerRemoves(_ photo: PhotoID, from robin: PersonID) async throws {
        try actions.pictureRemoved(photo, from: robin)
        try await library.remove(photo, from: .entity(EntityID(rawValue: robin.rawValue)))
    }
}

@Test func aPictureTheOwnerRemovedStaysRemovedAcrossACheck() async throws {
    let f = try Fixture()
    let (robin, copy) = try await f.robinWithTheCopy()
    try await f.ownerRemoves(copy, from: robin)
    #expect(try f.person(robin).contactPhotoID == nil)

    try await f.actions.check()
    try await f.actions.copyPicture(for: robin)
    #expect(try f.photos(of: robin).isEmpty, "the owner's removal is kept")
    #expect(try f.photoRows() == 0)
    #expect(try f.store.people.declinedContacts(of: robin).isEmpty, "the marker is not a declined contact")
    #expect(try f.person(robin).contactIdentifier == "c-vale", "the link stays")
}

@Test func aFreshLinkAfterUnlinkCopiesThePictureAgain() async throws {
    let f = try Fixture()
    let (robin, copy) = try await f.robinWithTheCopy()
    try await f.ownerRemoves(copy, from: robin)
    try f.actions.unlink(robin)
    try await f.actions.link(robin, to: vale)
    #expect(try f.photos(of: robin).count == 1, "unlink forgets the removal")
    #expect(try f.person(robin).contactPhotoID != nil)
}

@Test func aLinkToAnotherContactCopiesThatPictureAndForgetsTheRemoval() async throws {
    let f = try Fixture()
    let (robin, copy) = try await f.robinWithTheCopy()
    try await f.ownerRemoves(copy, from: robin)
    try await f.actions.link(robin, to: reyes)
    #expect(try f.photos(of: robin).count == 1, "the other contact's picture is copied")
    #expect(try f.person(robin).contactPhotoID != nil)
    // Back to the first contact: a link to another contact cleared the removal, so its picture comes too.
    try await f.actions.link(robin, to: vale)
    #expect(try f.person(robin).contactPhotoID != nil)
}

@Test func aRemovalFollowsAContactTheSystemMerged() async throws {
    let f = try Fixture()
    let (robin, copy) = try await f.robinWithTheCopy()
    try await f.ownerRemoves(copy, from: robin)
    let merged = card("c-merged", "Robyn", "Vale")
    f.directory.cards = [merged, reyes]
    f.directory.merged = ["c-vale": "c-merged"]
    f.directory.pictures["c-merged"] = try f.picture("merged", rgb: 0x33AA66)

    try await f.actions.check()
    #expect(try f.person(robin).contactIdentifier == "c-merged")
    #expect(try f.photos(of: robin).isEmpty, "the same contact under its new identifier: the removal is kept")
}

@Test func removingAPhotoThatIsNotTheCopyMarksNothing() async throws {
    let f = try Fixture()
    let (robin, _) = try await f.robinWithTheCopy()
    let own = try await f.library.add(fileAt: try f.source("own", rgb: 0xAA3366), assetLocalID: nil, to: .entity(EntityID(rawValue: robin.rawValue)))
    let before = try f.dump()
    try f.actions.pictureRemoved(own.id, from: robin)
    #expect(try f.dump() == before, "only the app's copy is remembered")
}

// MARK: - The look again: details and a settled link (M-5, M-6, fix wave)

@Test func reguessMarksTheSessionsNewDetailLinksAsGuessesToo() async throws {
    let f = try Fixture()
    let (session, memories) = try f.keptSession([("Robyn loved the sea", ["Robyn"])])
    let robyn = try f.onlyPerson(memories[0])
    try await f.db.writer.write { db in
        try db.execute(sql: "insert into moment_entity (memory_id, entity_id, relation, origin) values (?, ?, 'detail', 'new')",
                       arguments: [memories[0].id.rawValue, robyn.rawValue])
    }
    let result = try await f.actions.reguess(session: session, contacts: [vale.forGuess])
    #expect(result.changedLinks == 1, "the count is of mention links")
    let detail = try f.store.entities.links(of: memories[0].id).first { $0.link.relation == .detail }
    #expect(detail?.link.origin == .assumed, "a fact about the person now hangs on a contact guess, and says so")
}

@Test func theLookAgainLinksNothingOnceTheNewLinkIsSettled() async throws {
    let f = try Fixture()
    let (session, memories) = try f.keptSession([("Robyn painted the fence", ["Robyn"])])
    let robyn = try f.onlyPerson(memories[0])
    // The owner settled the link between the look's read and its write.
    try await f.db.writer.write { db in
        try db.execute(sql: "update moment_entity set origin = 'confirmed' where memory_id = ?", arguments: [memories[0].id.rawValue])
    }
    let before = try f.dump()
    #expect(try f.store.people.linkFromReguess(robyn, to: vale.forGuess, saidName: "Robyn", in: session) == 0)
    #expect(try f.dump() == before, "no link, no rename: the look again did not link this person")
}
