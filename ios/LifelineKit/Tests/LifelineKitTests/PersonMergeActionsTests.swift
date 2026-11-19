import Foundation
import GRDB
import Testing
@testable import LifelineKit

// PC-c Task 2: two people become one, in one transaction. The person picked stays; the other joins them.
// Sample names are invented.

struct MergeEnv {
    let db: AppDatabase, store: ExtractionStore, keep: CandidateActions, actions: PersonMergeActions
    /// `contacts` are what Keep's guess sees, as the contacts cache gives them.
    init(contacts: [PersonGuess.Contact] = []) throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        var keep = CandidateActions(store: store)
        keep.contactsForGuess = { contacts }
        self.keep = keep
        actions = PersonMergeActions(store: store)
    }

    func session(_ texts: [String]) throws -> [SegmentID] {
        try StoreFixtures.session(in: store.sessions, segments: texts).1.map(\.id)
    }

    /// A waiting memory card in `segment` that names `people`.
    func card(in segment: SegmentID, people: [String]) throws -> Candidate {
        let text = try #require(try store.sessions.fetchSegment(segment)).text
        let out = MemoryOut(ref: "m0", kind: .event, title: "A title", quote: text,
                            segmentSpan: WordSpan(startWord: 0, endWord: text.split(separator: " ").count - 1),
                            peopleRefs: people, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: nil)
        let card = StoreFixtures.candidate(segment, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(card)
        return card
    }

    /// A kept memory that names no one; the test links it by hand, so each link's origin and role text are known.
    func memory(_ text: String) throws -> Memory {
        try keep.acceptMemory(try card(in: try session([text])[0], people: []), joinStory: false).memory
    }

    func link(_ memory: Memory, _ person: Person, _ relation: EntityRelation = .mention, role: String? = nil, origin: LinkOrigin?) throws {
        try store.entities.link(memory.id, person.entityID, relation: relation, roleText: role, origin: origin)
    }

    func person(_ id: PersonID) throws -> Person? { try store.people.person(id: id) }
    func entity(_ id: PersonID) throws -> Entity? { try store.entities.entity(id: EntityID(rawValue: id.rawValue)) }

    func photo(_ name: String, on person: Person) throws -> PhotoID {
        let photo = Self.photo(name)
        try store.photos.insert(photo, linkingTo: .entity(person.entityID))
        return photo.id
    }

    static func photo(_ name: String) -> Photo {
        Photo(fileName: "\(name).jpg", sha256: "hash-\(name)", pixelWidth: 400, pixelHeight: 300, addedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func page(_ person: PersonID) throws -> [PhotoID] { try store.photos.photos(of: .entity(EntityID(rawValue: person.rawValue))).map(\.photo.id) }

    func covers(_ person: PersonID) throws -> Int {
        try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link where entity_id = ? and role = 'cover'", arguments: [person.rawValue]) ?? 0 }
    }

    func sql(_ sql: String, _ arguments: StatementArguments = []) throws {
        try db.writer.write { try $0.execute(sql: sql, arguments: arguments) }
    }

    /// Every row a merge can touch, as text, so two states compare exactly. `domain_tag` is read only while it exists.
    func dump() throws -> [String] {
        try db.writer.read { db in
            var out: [String] = []
            var tables = ["person", "entity", "moment_entity", "alias", "entity_span", "photo_link", "photo_page_declined", "mention",
                          "candidate_person_choice", "curiosity_item", "session", "contact_declined"]
            if try db.tableExists("domain_tag") { tables.append("domain_tag") }
            if try db.tableExists("memory_person") { tables.append("memory_person") }
            for table in tables {
                out += try Row.fetchAll(db, sql: "select * from \(table)").map { "\(table): \($0.description)" }.sorted()
            }
            return out
        }
    }
}

private let valeContact = PersonGuess.Contact(identifier: "c-vale", fullName: "Robyn Vale", givenName: "Robyn", nickname: "")

// MARK: - Links

@Test func everyLinkJoinsTheStayingPersonWithItsOriginAndRole() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let (a, b, fact, c) = (try env.memory("Robin painted the fence"), try env.memory("Robin fixed the gate"),
                           try env.memory("Robin is a carpenter"), try env.memory("Robyn cut the grass"))
    try env.link(a, robin, role: "Robin", origin: .assumed)
    try env.link(b, robin, role: "my roommate", origin: .confirmed)
    try env.link(fact, robin, .detail, role: nil, origin: .confirmed)
    try env.link(c, robyn, role: "Robyn", origin: .said)

    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    #expect(receipt.staying == robyn.id && receipt.leaving == robin.id && receipt.stayingName == "Robyn Vale")

    let links = try env.store.entities.links(to: robyn.entityID)
        .map { "\($0.memoryID == a.id ? "a" : $0.memoryID == b.id ? "b" : $0.memoryID == c.id ? "c" : "fact")|\($0.relation.rawValue)|\($0.roleText ?? "-")|\($0.origin?.rawValue ?? "-")" }
    #expect(Set(links) == ["a|mention|Robin|assumed", "b|mention|my roommate|confirmed", "fact|detail|-|confirmed", "c|mention|Robyn|said"])
    #expect(try env.person(robin.id) == nil)
    #expect(try env.entity(robin.id) == nil)
}

// Review Focus 2: a memory linked to both keeps one link, with the stronger origin.
@Test func aMemoryLinkedToBothKeepsOneLinkWithTheStrongerOrigin() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let m = try env.memory("Robin and Robyn painted the fence")
    try env.link(m, robin, role: "Robin", origin: .confirmed)
    try env.link(m, robyn, role: "Robyn", origin: .assumed)

    try env.actions.merge(robin.id, into: robyn.id)

    let rows = try env.store.entities.links(of: m.id).filter { $0.entity.type == .person }.map(\.link)
    #expect(rows.count == 1)
    #expect(rows.first?.entityID == robyn.entityID && rows.first?.origin == .confirmed)
    #expect(rows.first?.roleText == "Robyn", "the stayer's row stays (C2)")
}

// MARK: - Names

@Test func theLeavingPersonsAliasesAndNameJoinTheStayingPerson() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    try env.store.people.addAlias("Rob", to: robin.id)
    try env.store.people.addAlias("my roommate", to: robin.id)
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.store.people.aliasesOldestFirst(of: robyn.id).map(\.text) == ["Robyn Vale", "Robin", "Rob", "my roommate"])
    #expect(try env.person(robyn.id)?.displayName == "Robyn Vale")
}

@Test func aNameEqualToTheStayingNameIsNotAddedTwice() throws {
    let env = try MergeEnv()
    let leaving = try env.store.people.insertPerson(displayName: "robin ")
    let staying = try env.store.people.insertPerson(displayName: "Robin")
    try env.sql("delete from alias where person_id = ?", [leaving.id.rawValue])
    try env.actions.merge(leaving.id, into: staying.id)
    #expect(try env.store.people.aliasesOldestFirst(of: staying.id).map(\.text) == ["Robin"])
}

// Review Focus 3: nothing from a contact goes to the model, after a merge too.
@Test func theContactOfTheLeavingPersonMovesAndItsNameNeverBecomesAnAlias() throws {
    let env = try MergeEnv(contacts: [valeContact])
    let segment = try env.session(["Robyn painted the fence"])[0]
    let moment = try env.keep.acceptMemory(try env.card(in: segment, people: ["Robyn"]), joinStory: false).memory
    let made = try #require(try env.store.entities.links(of: moment.id).first { $0.entity.type == .person }.map { PersonID(rawValue: $0.entity.id.rawValue) })
    let leaving = try #require(try env.person(made))
    #expect(leaving.nameOrigin == .contact && leaving.contactIdentifier == "c-vale")
    // The picture the app copies from the contact, as `ContactLinkActions.copyPicture` records it.
    let picture = MergeEnv.photo("vale")
    try env.store.photos.insert(picture, linkingTo: .entity(leaving.entityID)) { db in
        try PeopleRepository.recordContactPhoto(picture.id, for: leaving.id, identifier: "c-vale", in: db)
    }
    let robin = try env.store.people.insertPerson(displayName: "Robin")

    try env.actions.merge(leaving.id, into: robin.id)

    let staying = try #require(try env.person(robin.id))
    #expect(staying.contactIdentifier == "c-vale" && staying.contactName == "Robyn Vale" && staying.contactState == Person.contactLinked)
    #expect(staying.contactPhotoID == picture.id)
    #expect(staying.displayName == "Robin")
    #expect(try env.page(robin.id) == [picture.id])
    let aliases = try env.store.people.aliasesOldestFirst(of: robin.id)
    #expect(aliases.map(\.text) == ["Robin", "Robyn"])
    #expect(!aliases.contains { $0.text.contains("Vale") }, "a contact's name is never an alias")

    let people = try env.store.people.peopleByRecentLink().map { ($0, try env.store.people.aliasesOldestFirst(of: $0.id)) }
    let seg = try #require(try env.store.sessions.fetchSegment(segment))
    let packet = ContextPacketBuilder.build(segment: seg, previous: [], people: people, memories: [], profileFreeText: nil, stage: "open")
    #expect(!String(decoding: try packet.encodedJSON(), as: UTF8.self).contains("Vale"), "the contact's name never reaches the model")
}

// MARK: - Refusals

@Test func twoPeopleWhoBothHoldAContactAreRefusedAndNothingChanges() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    try env.sql("update person set contact_identifier = 'c-hale', contact_name = 'Robin Hale', contact_state = 'linked' where id = ?", [robin.id.rawValue])
    try env.sql("update person set contact_identifier = 'c-vale', contact_name = 'Robyn Vale', contact_state = 'linked' where id = ?", [robyn.id.rawValue])
    let before = try env.dump()

    #expect(throws: PersonMergeActions.Error.twoContacts) { try env.actions.check(robin.id, into: robyn.id) }
    #expect(throws: PersonMergeActions.Error.twoContacts) { try env.actions.merge(robin.id, into: robyn.id) }
    #expect(try env.dump() == before)
}

@Test func theOwnerSamePersonAndAGonePersonAreRefused() throws {
    let env = try MergeEnv()
    try env.store.profile.save(Profile(displayName: "Sam", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let owner = try #require(try env.store.profile.owner())
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let before = try env.dump()

    #expect(throws: PersonMergeActions.Error.owner) { try env.actions.merge(owner.id, into: robin.id) }
    #expect(throws: PersonMergeActions.Error.owner) { try env.actions.merge(robin.id, into: owner.id) }
    #expect(throws: PersonMergeActions.Error.owner) { try env.actions.check(robin.id, into: owner.id) }
    #expect(throws: PersonMergeActions.Error.samePerson) { try env.actions.merge(robin.id, into: robin.id) }
    #expect(throws: PersonMergeActions.Error.samePerson) { try env.actions.check(robin.id, into: robin.id) }
    #expect(throws: PersonMergeActions.Error.notFound) { try env.actions.merge(PersonID(), into: robin.id) }
    #expect(throws: PersonMergeActions.Error.notFound) { try env.actions.check(robin.id, into: PersonID()) }
    #expect(try env.dump() == before)
}

// MARK: - Values

@Test func theStayingPersonKeepsTheirValuesAndTakesTheOthersWhereTheyHaveNone() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let born = Date(timeIntervalSince1970: 500_000_000)
    try env.sql("update person set notes = 'Lent me a bike' where id = ?", [robyn.id.rawValue])
    try env.sql("update person set notes = 'Plays the cello', birth_date = ?, birth_date_origin = 'stated' where id = ?", [born, robin.id.rawValue])
    try env.sql("update entity set detail_text = 'my old roommate' where id = ?", [robyn.id.rawValue])
    try env.sql("update entity set detail_text = 'a carpenter' where id = ?", [robin.id.rawValue])
    try env.store.entities.setStatedSpan(robin.entityID, .stated(between: 1990, and: 1995))

    try env.actions.merge(robin.id, into: robyn.id)

    let person = try #require(try env.person(robyn.id))
    #expect(person.notes == "Lent me a bike", "the stayer's value wins")
    #expect(person.birthDate == born && person.birthDateOrigin == .stated, "taken with its origin")
    #expect(person.nameOrigin == nil && person.displayName == "Robyn Vale")
    let entity = try #require(try env.entity(robyn.id))
    #expect(entity.detailText == "my old roommate")
    #expect(entity.range == .stated(between: 1990, and: 1995))
}

@Test func theStayingPersonsOwnDatesAndBirthDateWin() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let (mine, theirs) = (Date(timeIntervalSince1970: 400_000_000), Date(timeIntervalSince1970: 500_000_000))
    try env.sql("update person set birth_date = ?, birth_date_origin = 'typed' where id = ?", [mine, robyn.id.rawValue])
    try env.sql("update person set notes = 'Plays the cello', birth_date = ?, birth_date_origin = 'stated' where id = ?", [theirs, robin.id.rawValue])
    try env.sql("update entity set detail_text = 'a carpenter' where id = ?", [robin.id.rawValue])
    try env.store.entities.setStatedSpan(robyn.entityID, .stated(year: 2001))
    try env.store.entities.setStatedSpan(robin.entityID, .stated(between: 1990, and: 1995))

    try env.actions.merge(robin.id, into: robyn.id)

    let person = try #require(try env.person(robyn.id))
    #expect(person.notes == "Plays the cello")
    #expect(person.birthDate == mine && person.birthDateOrigin == .typed)
    let entity = try #require(try env.entity(robyn.id))
    #expect(entity.detailText == "a carpenter")
    #expect(entity.range == .stated(year: 2001))
}

// Plan decision 1: either side on means on, and the preview says so when the two differed.
@Test func hiddenAndKeptFromTheAIStayOnAndThePreviewSaysSo() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    try env.store.entities.setExcluded(robin.entityID, true)
    try env.store.entities.setHidden(robyn.entityID, true)

    let preview = try env.actions.check(robin.id, into: robyn.id)
    #expect(preview.leaving.id == robin.id && preview.staying.id == robyn.id)
    #expect(preview.staysOutOfAI && preview.staysHidden)

    try env.actions.merge(robin.id, into: robyn.id)
    let entity = try #require(try env.entity(robyn.id))
    #expect(entity.excludedFromAI && entity.hiddenFromTimeline)
}

@Test func equalFlagsGiveNoFlagLine() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    #expect(try env.actions.check(robin.id, into: robyn.id) == PersonMergePreview(leaving: robin, staying: robyn, staysHidden: false, staysOutOfAI: false))
    for id in [robin.entityID, robyn.entityID] {
        try env.store.entities.setExcluded(id, true)
        try env.store.entities.setHidden(id, true)
    }
    let preview = try env.actions.check(robin.id, into: robyn.id)
    #expect(!preview.staysHidden && !preview.staysOutOfAI, "both were on: nothing changes for either")
}

// Plan decision 6: a merge is the owner's act.
@Test func theStayingPersonIsNoLongerAGuess() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    try env.sql("update person set created_by_guess = 1 where id = ?", [robyn.id.rawValue])
    try env.actions.merge(robin.id, into: robyn.id)
    #expect(try env.person(robyn.id)?.createdByGuess == false)
}

// MARK: - Photos

// Review Focus 5: one order, the stayer's key photo first, one link to a shared photo, one cover.
@Test func photosKeepOneOrderWithTheStayersKeyPhotoFirst() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let s1 = try env.photo("s1", on: robyn), s2 = try env.photo("s2", on: robyn), shared = try env.photo("shared", on: robyn)
    let l1 = try env.photo("l1", on: robin)
    try env.store.photos.link(shared, to: .entity(robin.entityID))
    let l2 = try env.photo("l2", on: robin)
    #expect(try env.page(robin.id) == [l1, shared, l2])

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.page(robyn.id) == [s1, s2, shared, l1, l2])
    #expect(try env.covers(robyn.id) == 1)
    #expect(try env.store.photos.photos(of: .entity(robyn.entityID)).first { $0.role == .cover }?.photo.id == s1)
    #expect(try env.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from photo_link where photo_id = ?", arguments: [shared.rawValue]) } == 1)
}

@Test func theLeavingKeyPhotoBecomesTheKeyPhotoOfAStayerWithNone() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let l1 = try env.photo("l1", on: robin), l2 = try env.photo("l2", on: robin)
    try env.store.photos.setCover(l2, of: .entity(robin.entityID))

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.page(robyn.id) == [l2, l1])
    #expect(try env.covers(robyn.id) == 1)
}

@Test func anOwnersLinkToASharedPhotoOutlivesAStoryLink() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let shared = try env.photo("shared", on: robyn)
    try env.sql("update photo_link set origin = 'story' where photo_id = ?", [shared.rawValue])
    try env.store.photos.link(shared, to: .entity(robin.entityID))   // the owner's link: origin null

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.store.photos.storyPages(of: shared).isEmpty, "the owner put it on one of the two pages")
}

@Test func aPhotoTheOwnerTookOffTheLeavingPageStaysOffTheStayingPage() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let photo = MergeEnv.photo("p")
    try env.store.photos.insert(photo)
    try env.sql("insert into photo_page_declined (photo_id, entity_id) values (?, ?)", [photo.id.rawValue, robin.id.rawValue])

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.store.photos.isDeclined(photo.id, on: robyn.entityID))
}

// Ruling C4 (a): a photo the merged person holds is not also "taken off" their page, in either direction.
@Test func aPhotoTheStayerHoldsAfterTheMergeIsNotAlsoTakenOffTheirPage() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let onStayer = try env.photo("s1", on: robyn)    // the owner took it off the leaving page
    let onLeaving = try env.photo("l1", on: robin)   // the owner took it off the staying page
    try env.sql("insert into photo_page_declined (photo_id, entity_id) values (?, ?), (?, ?)",
                [onStayer.rawValue, robin.id.rawValue, onLeaving.rawValue, robyn.id.rawValue])

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.page(robyn.id) == [onStayer, onLeaving])
    #expect(try !env.store.photos.isDeclined(onStayer, on: robyn.entityID))
    #expect(try !env.store.photos.isDeclined(onLeaving, on: robyn.entityID))
}

// Ruling C4 (b): the stayer no longer declines the contact they now hold. A picture-removal marker stays.
@Test func theStayerNoLongerDeclinesTheContactTheyTake() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    try env.sql("update person set contact_identifier = 'c-vale', contact_name = 'Robyn Vale', contact_state = 'linked' where id = ?", [robin.id.rawValue])
    try env.sql("insert into contact_declined (person_id, contact_identifier) values (?, 'c-vale'), (?, 'picture:c-vale'), (?, 'c-other')",
                [robyn.id.rawValue, robyn.id.rawValue, robyn.id.rawValue])

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.person(robyn.id)?.contactIdentifier == "c-vale")
    #expect(try env.store.people.declinedContacts(of: robyn.id) == ["c-other"])
    #expect(try env.store.people.pictureWasRemoved(robyn.id, identifier: "c-vale"), "the marker is not a decline")
}

// Ruling C4 (b), the other direction: the stayer keeps their own contact, which the leaving person had declined.
@Test func theStayerDoesNotTakeADeclineOfTheirOwnContact() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    try env.sql("update person set contact_identifier = 'c-s', contact_name = 'Robyn Vale', contact_state = 'linked' where id = ?", [robyn.id.rawValue])
    try env.sql("insert into contact_declined (person_id, contact_identifier) values (?, 'c-s'), (?, 'picture:c-s'), (?, 'c-other')",
                [robin.id.rawValue, robin.id.rawValue, robin.id.rawValue])

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.person(robyn.id)?.contactIdentifier == "c-s")
    #expect(try env.store.people.declinedContacts(of: robyn.id) == ["c-other"])
    #expect(try env.store.people.pictureWasRemoved(robyn.id, identifier: "c-s"), "the marker is not a decline")
}

// Ruling C4 (c): the owner's words are kept. A stayer's link with no role text takes the leaving link's.
@Test func aStayersLinkWithNoRoleTextTakesTheLeavingLinksRoleText() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let (m, n) = (try env.memory("Robin and Robyn painted the fence"), try env.memory("Robin and Robyn fixed the gate"))
    try env.link(m, robin, role: "my roommate", origin: .confirmed)
    try env.link(m, robyn, role: nil, origin: .assumed)
    try env.link(n, robin, role: "my roommate", origin: .confirmed)
    try env.link(n, robyn, role: "Robyn", origin: .assumed)

    try env.actions.merge(robin.id, into: robyn.id)

    let roles = try [m, n].map { memory in try env.store.entities.links(of: memory.id).filter { $0.entity.type == .person }.map(\.link.roleText) }
    #expect(roles == [["my roommate"], ["Robyn"]], "the stayer's own role text wins (C2)")
}

// MARK: - What points at the person

// Review Focus 1: a stored choice cascades on its person, so it moves before the delete.
@Test func aChoiceOnAWaitingCardFollowsTheMergedPerson() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    // "Theo" matches no one, so only the stored choice can link the memory to the merged person.
    let card = try env.card(in: try env.session(["Theo painted the fence"])[0], people: ["Theo"])
    try PersonLinkActions(store: env.store).choose(.person(robin.id), for: "Theo", on: card.id)

    try env.actions.merge(robin.id, into: robyn.id)
    #expect(try env.db.writer.read { try String.fetchOne($0, sql: "select person_id from candidate_person_choice") } == robyn.id.rawValue)
    let memory = try env.keep.acceptMemory(card, joinStory: false).memory

    let people = try env.store.entities.links(of: memory.id).filter { $0.entity.type == .person }.map(\.entity.id)
    #expect(people == [robyn.entityID])
}

@Test func mentionsCuriosityTheSubjectTagsAndDeclinesFollowTheMergedPerson() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let (session, segments) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin painted the fence"])
    let mention = Mention(id: .init(), segmentID: segments[0].id, text: "Robin", status: .resolved, personID: robin.id)
    try env.store.people.insertMention(mention)
    let item = CuriosityItem(id: .init(), kind: .personWithoutMoment, text: "When did you meet Robin?", payoffCount: 0, status: .open,
                             sourceMemoryID: nil, targetMemoryID: nil, entityID: robin.entityID)
    try env.db.writer.write { try item.insert($0) }
    try env.sql("update session set subject_entity_id = ? where id = ?", [robin.id.rawValue, session.rawValue])
    try env.store.tags.tag(.entity, robin.id.rawValue, "family")
    try env.sql("insert into contact_declined (person_id, contact_identifier) values (?, 'c-other'), (?, 'picture:c-vale')",
                [robin.id.rawValue, robin.id.rawValue])

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.store.people.mention(id: mention.id)?.personID == robyn.id)
    #expect(try env.db.writer.read { try String.fetchOne($0, sql: "select entity_id from curiosity_item where id = ?", arguments: [item.id.rawValue]) } == robyn.id.rawValue)
    #expect(try env.db.writer.read { try String.fetchOne($0, sql: "select subject_entity_id from session where id = ?", arguments: [session.rawValue]) } == robyn.id.rawValue)
    #expect(try env.store.tags.tags(of: .entity, robyn.id.rawValue) == ["family"])
    #expect(try env.store.tags.tags(of: .entity, robin.id.rawValue).isEmpty, "no tag is left on an entity that is gone")
    let declined = try env.db.writer.read {
        try String.fetchAll($0, sql: "select contact_identifier from contact_declined where person_id = ? order by contact_identifier", arguments: [robyn.id.rawValue])
    }
    #expect(declined == ["c-other", "picture:c-vale"])
}

@Test func theLeavingFirstTellingFollowsTheStayersOwn() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let segments = try env.session(["Robyn cut the grass", "Robin painted the fence"])
    try env.store.entities.insertSpan(EntitySpan(entityID: robyn.entityID, segmentID: segments[0], startMs: 0, endMs: 900, order: 0))
    try env.store.entities.insertSpan(EntitySpan(entityID: robin.entityID, segmentID: segments[1], startMs: 100, endMs: 800, order: 0))

    try env.actions.merge(robin.id, into: robyn.id)

    #expect(try env.store.entities.spans(of: robyn.entityID) == [
        EntitySpan(entityID: robyn.entityID, segmentID: segments[0], startMs: 0, endMs: 900, order: 0),
        EntitySpan(entityID: robyn.entityID, segmentID: segments[1], startMs: 100, endMs: 800, order: 1),
    ])
}

// MARK: - The picker's list

@Test func othersLeavesOutThePersonAndTheOwner() throws {
    let env = try MergeEnv()
    try env.store.profile.save(Profile(displayName: "Sam", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let theo = try env.store.people.insertPerson(displayName: "Theo")
    let m = try env.memory("Theo fixed the gate")
    try env.link(m, theo, origin: .confirmed)

    #expect(try env.actions.others(than: robin.id).map(\.id) == [theo.id, robyn.id], "most recently linked first")
}

// MARK: - One transaction

@Test func aFailureInsideTheMergeLeavesBothPeopleAsTheyWere() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let m = try env.memory("Robin painted the fence")
    try env.link(m, robin, role: "Robin", origin: .assumed)
    _ = try env.photo("l1", on: robin)
    try env.sql("drop table domain_tag")   // the merge's tag step throws
    let before = try env.dump()

    #expect(throws: (any Error).self) { try env.actions.merge(robin.id, into: robyn.id) }
    #expect(try env.dump() == before)
    #expect(try env.person(robin.id) != nil)
}
