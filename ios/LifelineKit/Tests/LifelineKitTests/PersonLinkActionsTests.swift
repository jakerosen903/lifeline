import Foundation
import GRDB
import Testing
@testable import LifelineKit

// Task 5 (PC2/PC3): settle a guess, move a name to another person, and Undo. Every action is one
// transaction; Undo never overwrites later work.

private struct Env {
    let db: AppDatabase, store: ExtractionStore, keep: CandidateActions, actions: PersonLinkActions
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        keep = CandidateActions(store: store)
        actions = PersonLinkActions(store: store)
    }

    func session(_ texts: [String]) throws -> [SegmentID] {
        try StoreFixtures.session(in: store.sessions, segments: texts).1.map(\.id)
    }

    /// A waiting memory card in `segment`, with a person card for each `(name, ref, relation)`.
    func card(in segment: SegmentID, people: [String], kind: MemoryKind = .event, about: String? = nil,
              mentions: [(String, String?, String?)] = []) throws -> Candidate {
        let text = try #require(try store.sessions.fetchSegment(segment)).text
        let ordinal = try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from candidate where segment_id = ?", arguments: [segment.rawValue]) ?? 0 }
        let out = MemoryOut(ref: "m\(ordinal)", kind: kind, title: "A title", quote: text,
                            segmentSpan: WordSpan(startWord: 0, endWord: text.split(separator: " ").count - 1),
                            peopleRefs: people, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: about)
        let card = StoreFixtures.candidate(segment, ordinal: ordinal, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(card)
        for (index, (name, ref, relation)) in mentions.enumerated() {
            let mention = MentionOut(text: name, kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, relationText: relation, ref: ref)
            try store.candidates.insert(StoreFixtures.candidate(segment, ordinal: ordinal + index + 1, kind: .person, payload: try CandidatePayload.encode(mention)))
        }
        return card
    }

    /// A card kept the way the owner keeps it: the guess decides each said name.
    func kept(in segment: SegmentID, people: [String], kind: MemoryKind = .event, about: String? = nil,
              mentions: [(String, String?, String?)] = []) throws -> Memory {
        try keep.acceptMemory(try card(in: segment, people: people, kind: kind, about: about, mentions: mentions), joinStory: false).memory
    }

    /// The memory's link to `person`, or to its only person.
    func link(_ memory: Memory, of person: PersonID? = nil, relation: EntityRelation = .mention) throws -> PersonLink {
        let id = try person ?? onlyPerson(memory, relation)
        return try #require(try store.personLinks.links(to: id).first { $0.memoryID == memory.id && $0.relation == relation })
    }

    func onlyPerson(_ memory: Memory, _ relation: EntityRelation = .mention) throws -> PersonID {
        let rows = try personRows(memory, relation)
        try #require(rows.count == 1)
        return PersonID(rawValue: rows[0].entityID.rawValue)
    }

    func personRows(_ memory: Memory, _ relation: EntityRelation = .mention) throws -> [MomentEntity] {
        try store.entities.links(of: memory.id).filter { $0.entity.type == .person && $0.link.relation == relation }.map(\.link)
    }

    func aliases(_ person: PersonID) throws -> [String] { try store.people.aliases(of: person).map(\.text) }

    func firstTelling(_ person: PersonID) throws -> EntitySpan? {
        try store.entities.spans(of: EntityID(rawValue: person.rawValue)).first { $0.order == 0 }
    }

    func firstSpan(_ memory: Memory) throws -> MemorySpan { try #require(try store.memories.spans(of: memory.id).first { $0.order == 0 }) }

    /// Every row the feature can touch, as text, so two states compare exactly.
    func dump() throws -> [String] {
        try db.writer.read { db in
            var out: [String] = []
            for table in ["person", "entity", "moment_entity", "alias", "entity_span", "candidate_person_choice"] {
                out += try Row.fetchAll(db, sql: "select * from \(table)").map { "\(table): \($0.description)" }.sorted()
            }
            return out
        }
    }

    func count(_ table: String) throws -> Int { try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from \(table)") ?? 0 } }
}

// MARK: - Settle

@Test func settleConfirmsOneLinkOrTheGroup() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let segs = try env.session(["Robin painted the fence", "Robin fixed the gate", "Robin cut the grass"])
    let memories = try segs.map { try env.kept(in: $0, people: ["Robin"]) }
    #expect(try memories.map { try env.link($0).origin } == [.assumed, .assumed, .assumed])

    try env.actions.settle(try env.link(memories[0]), wholeGroup: false)
    #expect(try memories.map { try env.link($0).origin } == [.confirmed, .assumed, .assumed], "only the tapped link settles")

    try env.actions.settle(try env.link(memories[1]), wholeGroup: true)
    #expect(try memories.map { try env.link($0).origin } == [.confirmed, .confirmed, .confirmed])
    #expect(try env.onlyPerson(memories[2]) == robin.id)
}

@Test func settleSavesTheRelationOnlyNow() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let m = try env.kept(in: try env.session(["my roommate Robin painted the fence"])[0], people: ["my roommate, Robin"])
    #expect(try env.aliases(robin.id) == ["Robin"], "a guess teaches no name")
    try env.actions.settle(try env.link(m), wholeGroup: false)
    #expect(Set(try env.aliases(robin.id)) == ["Robin", "my roommate"])
}

@Test func settleClearsTheGuessFlagOfANewPerson() throws {
    let env = try Env()
    let m = try env.kept(in: try env.session(["Tomas painted the fence"])[0], people: ["Tomas"])
    let tomas = try env.onlyPerson(m)
    #expect(try env.store.people.person(id: tomas)?.createdByGuess == true)
    try env.actions.settle(try env.link(m), wholeGroup: false)
    #expect(try env.store.people.person(id: tomas)?.createdByGuess == false, "the owner stands behind this person now")
    #expect(try env.link(m).origin == .confirmed)
}

@Test func settleOfAConfirmedLinkChangesNothing() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let m = try env.kept(in: try env.session(["my roommate Robin painted the fence"])[0], people: ["my roommate, Robin"])
    try env.store.memories.link(robin.id, to: m.id, roleText: nil, origin: .confirmed)
    let before = try env.dump()
    try env.actions.settle(try env.link(m), wholeGroup: false)
    #expect(try env.dump() == before, "a no-op that still succeeds")
}

@Test func aLinkThatIsGoneIsNotFound() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let m = try env.kept(in: try env.session(["Robin painted the fence"])[0], people: ["Robin"])
    let link = try env.link(m)
    try env.store.entities.unlink(m.id, robin.entityID, relation: .mention)
    #expect(throws: PersonLinkActions.Error.notFound) { try env.actions.settle(link, wholeGroup: false) }
    #expect(throws: PersonLinkActions.Error.notFound) { try env.actions.move(link, to: .person(robyn.id), wholeGroup: false) }
    let other = try env.kept(in: try env.session(["Robin dug the bed"])[0], people: ["Robin"])
    #expect(throws: PersonLinkActions.Error.notFound) { try env.actions.move(try env.link(other), to: .person(PersonID()), wholeGroup: false) }
    // A double tap: the second move reads the link again and finds it gone.
    let tapped = try env.link(other)
    try env.actions.move(tapped, to: .person(robyn.id), wholeGroup: false)
    #expect(throws: PersonLinkActions.Error.notFound) { try env.actions.move(tapped, to: .person(robyn.id), wholeGroup: false) }
}

// MARK: - Move

@Test func moveRepointsTheLinkAndKeepsTheSaidName() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let m = try env.kept(in: try env.session(["my roommate Robin painted the fence"])[0], people: ["my roommate, Robin"])
    let receipt = try env.actions.move(try env.link(m), to: .person(robyn.id), wholeGroup: false)

    let rows = try env.personRows(m)
    #expect(rows.map(\.entityID) == [robyn.entityID])
    #expect(rows.map(\.origin) == [.confirmed])
    #expect(rows.map(\.roleText) == ["my roommate, Robin"], "the owner's words stay as said")
    #expect(Set(try env.aliases(robyn.id)) == ["Robyn Vale", "Robin", "my roommate"])
    #expect(try env.aliases(robin.id) == ["Robin"], "the old person keeps their aliases")
    #expect(receipt.newName == "Robyn Vale")
    #expect(Set(receipt.addedAliases.map(\.text)) == ["Robin", "my roommate"])
}

@Test func moveCarriesTheGroupInOneRecordingOnly() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let here = try env.session(["Robin painted the fence", "Robin fixed the gate", "Robin cut the grass"])
    let memories = try here.map { try env.kept(in: $0, people: ["Robin"]) }
    let elsewhere = try env.kept(in: try env.session(["Robin called"])[0], people: ["Robin"])

    let receipt = try env.actions.move(try env.link(memories[1]), to: .person(robyn.id), wholeGroup: true)
    #expect(try memories.map { try env.onlyPerson($0) } == [robyn.id, robyn.id, robyn.id])
    #expect(try env.onlyPerson(elsewhere) == robin.id, "an answer never carries to another recording")
    #expect(receipt.before.count == 3 && receipt.after.count == 3)
}

@Test func moveWithoutTheGroupMovesOne() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let memories = try env.session(["Robin painted the fence", "Robin fixed the gate"]).map { try env.kept(in: $0, people: ["Robin"]) }
    try env.actions.move(try env.link(memories[0]), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.onlyPerson(memories[0]) == robyn.id)
    #expect(try env.onlyPerson(memories[1]) == robin.id)
    #expect(try env.link(memories[1]).origin == .assumed)
}

@Test func moveOntoAPersonAlreadyInTheMomentLeavesOneConfirmedLink() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let m = try env.kept(in: try env.session(["Robin and Robyn Vale painted the fence"])[0], people: ["Robin", "Robyn Vale"])
    #expect(Set(try env.personRows(m).map(\.entityID)) == [robin.entityID, robyn.entityID])

    let receipt = try env.actions.move(try env.link(m, of: robin.id), to: .person(robyn.id), wholeGroup: false)
    let rows = try env.personRows(m)
    #expect(rows.map(\.entityID) == [robyn.entityID], "a memory has at most one link to a person")
    #expect(rows.map(\.origin) == [.confirmed])
    #expect(rows.map(\.roleText) == ["Robyn Vale"], "the link that was there stays")
    #expect(receipt.before.count == 2, "both rows the move touched, as they were")
}

@Test func moveToTheSamePersonSettles() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let m = try env.kept(in: try env.session(["my roommate Robin painted the fence"])[0], people: ["my roommate, Robin"])
    let receipt = try env.actions.move(try env.link(m), to: .person(robin.id), wholeGroup: false)
    #expect(try env.link(m).origin == .confirmed)
    #expect(try env.onlyPerson(m) == robin.id)
    #expect(Set(try env.aliases(robin.id)) == ["Robin", "my roommate"])
    try env.actions.undo(receipt)
    #expect(try env.link(m).origin == .assumed, "Undo takes the settle back too")
    #expect(try env.aliases(robin.id) == ["Robin"])
}

@Test func moveTakesTheFactsAboutThatNameAndLeavesHandPlacedOnes() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let segs = try env.session(["Robin painted the fence", "Robin is the kindest person I know", "I always loved the garden"])
    let event = try env.kept(in: segs[0], people: ["Robin"])
    let fact = try env.kept(in: segs[1], people: ["Robin"], kind: .fact, about: "p1", mentions: [("Robin", "p1", nil)])
    let handPlaced = try env.kept(in: segs[2], people: [], kind: .fact)
    try env.store.entities.moveDetail(handPlaced.id, to: robin.entityID)
    #expect(try env.onlyPerson(fact, .detail) == robin.id)

    try env.actions.move(try env.link(event), to: .person(robyn.id), wholeGroup: true)
    #expect(try env.onlyPerson(event) == robyn.id)
    #expect(try env.onlyPerson(fact) == robyn.id, "the fact's own mention is in the group")
    #expect(try env.onlyPerson(fact, .detail) == robyn.id, "the fact about that name follows it")
    #expect(try env.personRows(fact, .detail).map(\.origin) == [.confirmed])
    #expect(try env.onlyPerson(handPlaced, .detail) == robin.id, "a detail the owner placed by hand stays")
}

@Test func moveGivesTheOldPersonAnotherFirstTelling() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let first = try env.kept(in: try env.session(["Robin painted the fence"])[0], people: ["Robin"])
    let later = try env.kept(in: try env.session(["Robin fixed the gate"])[0], people: ["Robin"])
    #expect(try env.firstTelling(robin.id)?.segmentID == env.firstSpan(first).segmentID)
    #expect(try env.firstTelling(robyn.id) == nil)

    try env.actions.move(try env.link(first), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.firstTelling(robin.id)?.segmentID == env.firstSpan(later).segmentID, "the oldest remaining moment")
    #expect(try env.firstTelling(robyn.id)?.segmentID == env.firstSpan(first).segmentID, "a person with none takes one")

    try env.actions.move(try env.link(later), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.firstTelling(robin.id) == nil, "no moment remains")
    #expect(try env.firstTelling(robyn.id)?.segmentID == env.firstSpan(first).segmentID, "a person with one keeps it")
}

@Test func moveRemovesAnEmptyGuessedPersonOnly() throws {
    let env = try Env()
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    // Made by the guess, with nothing left: removed.
    let tomasMoment = try env.kept(in: try env.session(["Tomas painted the fence"])[0], people: ["Tomas"])
    let tomas = try env.onlyPerson(tomasMoment)
    let receipt = try env.actions.move(try env.link(tomasMoment), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.store.people.person(id: tomas) == nil)
    #expect(try env.store.entities.entity(id: EntityID(rawValue: tomas.rawValue)) == nil)
    #expect(receipt.removedPerson?.id == tomas)

    // Made by the guess, with a photo: stays.
    let kiraMoment = try env.kept(in: try env.session(["Kira painted the fence"])[0], people: ["Kira"])
    let kira = try env.onlyPerson(kiraMoment)
    try env.store.photos.insert(Photo(fileName: "kira.jpg", sha256: "hash-kira", pixelWidth: 400, pixelHeight: 300, addedAt: .now),
                                linkingTo: .entity(EntityID(rawValue: kira.rawValue)))
    #expect(try env.actions.move(try env.link(kiraMoment), to: .person(robyn.id), wholeGroup: false).removedPerson == nil)
    #expect(try env.store.people.person(id: kira) != nil)

    // Not made by a guess: stays.
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robinMoment = try env.kept(in: try env.session(["Robin painted the fence"])[0], people: ["Robin"])
    #expect(try env.actions.move(try env.link(robinMoment), to: .person(robyn.id), wholeGroup: false).removedPerson == nil)
    #expect(try env.store.people.person(id: robin.id) != nil)

    // Made by the guess, still in another moment: stays.
    let segs = try env.session(["Ines painted the fence", "Ines fixed the gate"])
    let ines = try segs.map { try env.kept(in: $0, people: ["Ines"]) }
    #expect(try env.actions.move(try env.link(ines[0]), to: .person(robyn.id), wholeGroup: false).removedPerson == nil)
    #expect(try env.store.people.person(id: env.onlyPerson(ines[1])) != nil)
}

@Test func someoneNewMakesAPersonThatIsNotAGuess() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let m = try env.kept(in: try env.session(["my roommate Robin painted the fence"])[0], people: ["my roommate, Robin"])
    let receipt = try env.actions.move(try env.link(m), to: .someoneNew, wholeGroup: false)
    let created = try #require(receipt.createdPerson)
    let person = try #require(try env.store.people.person(id: created))
    #expect(person.displayName == "Robin" && !person.createdByGuess && person.nameOrigin == .said)
    #expect(created != robin.id)
    #expect(try env.onlyPerson(m) == created)
    #expect(try env.link(m).origin == .confirmed)
    #expect(Set(try env.aliases(created)) == ["Robin", "my roommate"])
    #expect(receipt.newName == "Robin")
    #expect(try env.store.people.person(id: robin.id) != nil)
}

@Test func notAPersonRemovesTheLinkAndSavesNoAlias() throws {
    let env = try Env()
    let will = try env.store.people.insertPerson(displayName: "Will")
    let m = try env.kept(in: try env.session(["my friend Will painted the fence"])[0], people: ["my friend, Will"])
    let receipt = try env.actions.move(try env.link(m), to: .notAPerson, wholeGroup: false)
    #expect(try env.personRows(m).isEmpty)
    #expect(try env.aliases(will.id) == ["Will"])
    #expect(receipt.addedAliases.isEmpty && receipt.after.isEmpty)
    #expect(try env.store.people.person(id: will.id) != nil, "a person the owner made stays")

    let faith = try env.kept(in: try env.session(["Faith carried me through"])[0], people: ["Faith"])
    let guessed = try env.onlyPerson(faith)
    #expect(try env.actions.move(try env.link(faith), to: .notAPerson, wholeGroup: false).removedPerson?.id == guessed)
    #expect(try env.store.people.person(id: guessed) == nil, "the empty guess goes")
}

// MARK: - Undo

@Test func undoRestoresEveryRowAndTheRemovedPerson() throws {
    let env = try Env()
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    try env.store.people.addAlias("my friend", to: robyn.id)
    let segs = try env.session(["my friend Tomas painted the fence", "my friend Tomas is the kindest person I know"])
    let m = try env.kept(in: segs[0], people: ["my friend, Tomas"])
    _ = try env.kept(in: segs[1], people: ["my friend, Tomas"], kind: .fact, about: "p1", mentions: [("Tomas", "p1", "my friend")])
    let before = try env.dump()

    let receipt = try env.actions.move(try env.link(m), to: .person(robyn.id), wholeGroup: true)
    #expect(receipt.removedPerson != nil)
    #expect(receipt.addedAliases.map(\.text) == ["Tomas"], "an alias Robyn already had is not added")
    try env.actions.undo(receipt)
    #expect(try env.dump() == before, "every row as it was")
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.undo(receipt) }
    #expect(try env.dump() == before, "a second Undo changes nothing")
    #expect(Set(try env.aliases(robyn.id)) == ["Robyn Vale", "my friend"])

    // "Someone new" undone: the person it made goes.
    let receipt2 = try env.actions.move(try env.link(m), to: .someoneNew, wholeGroup: true)
    try env.actions.undo(receipt2)
    #expect(try env.dump() == before)
}

@Test func undoIsRefusedWhenALinkChangedSince() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let kira = try env.store.people.insertPerson(displayName: "Kira")
    let m = try env.kept(in: try env.session(["Robin painted the fence"])[0], people: ["Robin"])

    let first = try env.actions.move(try env.link(m), to: .person(robyn.id), wholeGroup: false)
    try env.actions.move(try env.link(m), to: .person(kira.id), wholeGroup: false)
    let later = try env.dump()
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.undo(first) }
    #expect(try env.dump() == later, "a refused Undo changes nothing")

    // The owner put the old person back by hand: the row the move deleted is there again.
    let second = try env.actions.move(try env.link(m), to: .person(robyn.id), wholeGroup: false)
    try env.store.memories.link(kira.id, to: m.id, roleText: "Kira")
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.undo(second) }
    #expect(Set(try env.personRows(m).map(\.entityID)) == [robyn.entityID, kira.entityID])
}

@Test func undoOfSomeoneNewIsRefusedOnceThatPersonHasMore() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let segs = try env.session(["Robin painted the fence", "I met someone at the lake"])
    let m = try env.kept(in: segs[0], people: ["Robin"])
    let other = try env.kept(in: segs[1], people: [])
    let receipt = try env.actions.move(try env.link(m), to: .someoneNew, wholeGroup: false)
    let created = try #require(receipt.createdPerson)
    try env.store.memories.link(created, to: other.id, roleText: nil)
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.undo(receipt) }
    #expect(try env.store.people.person(id: created) != nil, "Undo never deletes later work")
}

@Test func aKillMidMoveLeavesOneState() throws {
    let env = try Env()
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let segs = try env.session(["Tomas painted the fence", "Tomas fixed the gate"])
    let memories = try segs.map { try env.kept(in: $0, people: ["Tomas"]) }
    let before = try env.dump()
    // A kill at the last write of the move: removing the empty guess.
    try env.db.writer.write { db in
        try db.execute(sql: "create trigger kill_move before delete on entity begin select raise(abort, 'killed'); end")
    }
    #expect(throws: (any Error).self) { try env.actions.move(try env.link(memories[0]), to: .person(robyn.id), wholeGroup: true) }
    #expect(try env.dump() == before, "the old state, every row")
}

// MARK: - Before Keep

@Test func aChoiceBeforeKeepIsStoredAndPreviewed() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let seg = try env.session(["my roommate Robin and Tomas and our parents painted the fence"])[0]
    let card = try env.card(in: seg, people: ["my roommate, Robin", "Tomas", "our parents"])

    let guessed = try env.actions.preview(card)
    #expect(guessed == [PreviewChip(saidName: "my roommate, Robin", name: "Robin", origin: .assumed, person: robin.id),
                        PreviewChip(saidName: "Tomas", name: "Tomas", origin: .new, person: nil)], "a group phrase gives no chip")
    #expect(guessed.first?.id == SaidName.key("my roommate, Robin"))

    try env.actions.choose(.person(robyn.id), for: "My roommate, Robin ", on: card.id)
    try env.actions.choose(.someoneNew, for: "Tomas", on: card.id)
    #expect(try env.actions.preview(card) == [PreviewChip(saidName: "my roommate, Robin", name: "Robyn Vale", origin: .confirmed, person: robyn.id),
                                               PreviewChip(saidName: "Tomas", name: "Tomas", origin: .confirmed, person: nil)])

    try env.actions.choose(.notAPerson, for: "Tomas", on: card.id)
    #expect(try env.count("candidate_person_choice") == 2, "choosing again replaces the row")
    #expect(try env.actions.preview(card).map(\.saidName) == ["my roommate, Robin"])

    let memory = try env.keep.acceptMemory(card, joinStory: false).memory
    #expect(try env.personRows(memory).map(\.entityID) == [robyn.entityID], "Keep applies what the sheet stored")
    #expect(try env.personRows(memory).map(\.origin) == [.confirmed])
}

@Test func aChoiceOnACardThatNoLongerWaitsIsRefused() throws {
    let env = try Env()
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let card = try env.card(in: try env.session(["Robin painted the fence"])[0], people: ["Robin"])
    _ = try env.keep.acceptMemory(card, joinStory: false)
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.choose(.person(robyn.id), for: "Robin", on: card.id) }
    #expect(throws: PersonLinkActions.Error.notFound) { try env.actions.choose(.notAPerson, for: "Robin", on: CandidateID()) }
    let waiting = try env.card(in: try env.session(["Robin fixed the gate"])[0], people: ["Robin"])
    #expect(throws: PersonLinkActions.Error.notFound) { try env.actions.choose(.person(PersonID()), for: "Robin", on: waiting.id) }
    #expect(throws: PersonLinkActions.Error.notFound) { try env.actions.choose(.notAPerson, for: "  ", on: waiting.id) }
    #expect(try env.count("candidate_person_choice") == 0)
}

@Test func previewWritesNothing() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let card = try env.card(in: try env.session(["Robin and Tomas and my aunt painted the fence"])[0], people: ["Robin", "Tomas", "my aunt"])
    let counts = try ["person", "entity", "moment_entity", "alias"].map { try env.count($0) }
    #expect(try env.actions.preview(card).count == 3)
    #expect(try ["person", "entity", "moment_entity", "alias"].map { try env.count($0) } == counts)
}

@Test func aFactFollowsTheStoredChoiceForItsName() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let seg = try env.session(["my roommate Robin is the kindest person I know"])[0]
    let card = try env.card(in: seg, people: ["my roommate, Robin"], kind: .fact, about: "p1", mentions: [("Robin", "p1", "my roommate")])
    try env.actions.choose(.person(robyn.id), for: "my roommate, Robin", on: card.id)
    let memory = try env.keep.acceptMemory(card, joinStory: false).memory
    #expect(try env.onlyPerson(memory) == robyn.id)
    #expect(try env.onlyPerson(memory, .detail) == robyn.id, "the detail and the mention reach one person")
    #expect(try env.personRows(memory, .detail).map(\.origin) == [.confirmed])
}

// MARK: - Rename

@Test func renameClearsCreatedByGuess() throws {
    let env = try Env()
    let m = try env.kept(in: try env.session(["Tomas painted the fence"])[0], people: ["Tomas"])
    let tomas = try env.onlyPerson(m)
    try env.store.people.rename(tomas, to: "Tomas Reyes")
    let person = try #require(try env.store.people.person(id: tomas))
    #expect(!person.createdByGuess, "a name the owner typed is not a guess")
    #expect(person.nameOrigin == .typed)
}

// MARK: - Review fixes (round 2)

@Test func aFactsOwnMentionAndItsDetailMoveTogether() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let segs = try env.session(["Robin painted the fence", "Robin is the kindest person I know"])
    let event = try env.kept(in: segs[0], people: ["Robin"])
    let fact = try env.kept(in: segs[1], people: ["Robin"], kind: .fact, about: "p1", mentions: [("Robin", "p1", nil)])
    #expect(try env.store.personLinks.group(of: try env.link(fact)).count == 2)

    try env.actions.move(try env.link(fact), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.onlyPerson(fact) == robyn.id)
    #expect(try env.onlyPerson(fact, .detail) == robyn.id, "a fact's mention and its detail never part")
    #expect(try env.personRows(fact).map(\.origin) == [.confirmed])
    #expect(try env.personRows(fact, .detail).map(\.origin) == [.confirmed])
    #expect(try env.onlyPerson(event) == robin.id, "the checkbox was off")
}

// I1 / R38: a fact linked by a packet person id moves with its memory's mention.
@Test func aFactLinkedByAPacketIDMovesWithItsMention() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let roommate = try env.store.people.insertPerson(displayName: "Robin")
    try env.store.people.addAlias("my roommate", to: roommate.id)
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let segs = try env.session(["Robin painted the fence", "Robin is allergic to peanuts", "Robin is the kindest person I know"])
    let event = try env.kept(in: segs[0], people: ["Robin, my roommate"])
    let alone = try env.kept(in: segs[1], people: ["Robin, my roommate"], kind: .fact, about: roommate.id.rawValue)
    let grouped = try env.kept(in: segs[2], people: ["Robin, my roommate"], kind: .fact, about: roommate.id.rawValue)
    #expect(try env.onlyPerson(alone, .detail) == roommate.id)

    try env.actions.move(try env.link(alone), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.onlyPerson(alone) == robyn.id)
    #expect(try env.onlyPerson(alone, .detail) == robyn.id, "the fact's mention and its detail never part")
    #expect(try env.onlyPerson(grouped, .detail) == roommate.id, "the checkbox was off")

    try env.actions.move(try env.link(event), to: .person(robyn.id), wholeGroup: true)
    #expect(try env.onlyPerson(grouped) == robyn.id)
    #expect(try env.onlyPerson(grouped, .detail) == robyn.id, "the detail moves with the group")
    #expect(try env.personRows(grouped, .detail).map(\.origin) == [.confirmed])
}

@Test func aMoveClearsTheTargetsGuessFlagAndUndoPutsItBack() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let segs = try env.session(["Tomas painted the fence", "Robin fixed the gate"])
    let tomas = try env.onlyPerson(try env.kept(in: segs[0], people: ["Tomas"]))
    let m = try env.kept(in: segs[1], people: ["Robin"])
    let receipt = try env.actions.move(try env.link(m), to: .person(tomas), wholeGroup: false)
    #expect(try env.store.people.person(id: tomas)?.createdByGuess == false, "the owner picked this person")
    try env.actions.undo(receipt)
    #expect(try env.store.people.person(id: tomas)?.createdByGuess == true)
}

@Test func undoOfAMoveThatChangedNothingDoesNothing() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let m = try env.kept(in: try env.session(["Robin painted the fence"])[0], people: ["Robin"])
    try env.actions.settle(try env.link(m), wholeGroup: false)
    let before = try env.dump()
    let receipt = try env.actions.move(try env.link(m), to: .person(robin.id), wholeGroup: false)
    #expect(receipt.before.isEmpty && receipt.after.isEmpty)
    try env.actions.undo(receipt)
    #expect(try env.dump() == before)
}

@Test func undoIsRefusedAfterARenameOfAPersonItWouldReflagOrDelete() throws {
    let env = try Env()
    // A settle cleared the guess flag; the owner then named the person.
    let m = try env.kept(in: try env.session(["Tomas painted the fence"])[0], people: ["Tomas"])
    let tomas = try env.onlyPerson(m)
    let settled = try env.actions.move(try env.link(m), to: .person(tomas), wholeGroup: false)
    try env.store.people.rename(tomas, to: "Tomas Reyes")
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.undo(settled) }
    #expect(try env.store.people.person(id: tomas)?.createdByGuess == false, "a person the owner named is never a guess again")

    // "Someone new", then renamed: Undo must not delete them.
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let other = try env.kept(in: try env.session(["Robin fixed the gate"])[0], people: ["Robin"])
    let made = try env.actions.move(try env.link(other), to: .someoneNew, wholeGroup: false)
    let created = try #require(made.createdPerson)
    try env.store.people.rename(created, to: "Robin Hale")
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.undo(made) }
    #expect(try env.store.people.person(id: created) != nil)
}

@Test func undoIsRefusedWhenAMemoryWasDeletedSince() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Will")
    let m = try env.kept(in: try env.session(["Will painted the fence"])[0], people: ["Will"])
    let receipt = try env.actions.move(try env.link(m), to: .notAPerson, wholeGroup: false)
    try env.store.memories.delete(m.id)
    #expect(throws: PersonLinkActions.Error.stale) { try env.actions.undo(receipt) }
}

@Test func theFirstTellingIsNeverAFactOrAHiddenMoment() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let kira = try env.store.people.insertPerson(displayName: "Kira")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let segs = try env.session(["Robin and Kira painted the fence", "Robin and Kira are the kindest people I know",
                                "Robin and Kira fixed the gate", "Robin dug the bed"])
    let first = try env.kept(in: segs[0], people: ["Robin", "Kira"])
    _ = try env.kept(in: segs[1], people: ["Robin", "Kira"], kind: .fact)
    let hidden = try env.kept(in: segs[2], people: ["Robin", "Kira"])
    try env.store.memories.setHidden(hidden.id, true)
    let visible = try env.kept(in: segs[3], people: ["Robin"])

    try env.actions.move(try env.link(first, of: robin.id), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.firstTelling(robin.id)?.segmentID == env.firstSpan(visible).segmentID, "the oldest remaining moment that shows")
    try env.actions.move(try env.link(first, of: kira.id), to: .person(robyn.id), wholeGroup: false)
    #expect(try env.firstTelling(kira.id) == nil, "a fact or a hidden memory is no first telling")
}

@Test func undoOfNotAPersonPutsTheDetailsBack() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Faith")
    let segs = try env.session(["Faith carried me through", "Faith is what kept me going"])
    let m = try env.kept(in: segs[0], people: ["Faith"])
    let fact = try env.kept(in: segs[1], people: ["Faith"], kind: .fact, about: "p1", mentions: [("Faith", "p1", nil)])
    let before = try env.dump()
    let receipt = try env.actions.move(try env.link(m), to: .notAPerson, wholeGroup: true)
    #expect(try env.personRows(fact, .detail).isEmpty, "the fact about that name is about no one")
    try env.actions.undo(receipt)
    #expect(try env.dump() == before)
}

@Test func settleNeverSavesAGroupPhrase() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let m = try env.kept(in: try env.session(["Robin and our parents painted the fence"])[0], people: ["Robin"],
                         mentions: [("Robin", nil, "our parents")])
    #expect(GroupPhrase.isGroup("our parents"))
    try env.actions.settle(try env.link(m), wholeGroup: false)
    #expect(try env.aliases(robin.id) == ["Robin"], "a phrase for several people is no one person's name")
}

@Test func someoneNewOnALinkWithNoSaidNameUsesThePersonsName() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let m = try env.kept(in: try env.session(["I painted the fence"])[0], people: [])
    try env.store.entities.link(m.id, robin.entityID, relation: .mention, roleText: nil, origin: .assumed)
    let receipt = try env.actions.move(try env.link(m), to: .someoneNew, wholeGroup: false)
    let createdID = try #require(receipt.createdPerson)
    let created = try #require(try env.store.people.person(id: createdID))
    #expect(created.displayName == "Robin" && created.id != robin.id)
    #expect(try env.personRows(m).map(\.roleText) == [nil])
}
