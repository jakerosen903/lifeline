import Foundation
import GRDB
import Testing
@testable import LifelineKit

// Task 3 (PC-a): Keep links each said name through `PersonGuess`, and every link records how it was made.

private struct Env {
    let db: AppDatabase, store: ExtractionStore, actions: CandidateActions, linkActions: PersonLinkActions
    /// `contacts` are what the guess sees, as the contacts cache gives them.
    init(contacts: [PersonGuess.Contact] = []) throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        var actions = CandidateActions(store: store)
        actions.contactsForGuess = { contacts }
        self.actions = actions
        var linkActions = PersonLinkActions(store: store)
        linkActions.contactsForGuess = { contacts }
        self.linkActions = linkActions
    }

    /// One new session with one segment and a memory card naming `people`, plus a person card for
    /// each `(name, ref, relation)` the extractor found in that segment.
    func card(_ text: String = "Robin and I painted the fence that summer", kind: MemoryKind = .event, people: [String],
              about: String? = nil, mentions: [(String, String?, String?)] = []) throws -> Candidate {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        return try card(in: segs[0].id, text, kind: kind, people: people, about: about, mentions: mentions)
    }

    func card(in segment: SegmentID, _ text: String, kind: MemoryKind = .event, people: [String], about: String? = nil,
              mentions: [(String, String?, String?)] = [], ordinal: Int = 0) throws -> Candidate {
        let words = text.split(separator: " ").count
        let out = MemoryOut(ref: "m\(ordinal)", kind: kind, title: "A title", quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                            peopleRefs: people, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: about)
        let memory = StoreFixtures.candidate(segment, ordinal: ordinal, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(memory)
        for (index, (name, ref, relation)) in mentions.enumerated() {
            let mention = MentionOut(text: name, kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, relationText: relation, ref: ref)
            try store.candidates.insert(StoreFixtures.candidate(segment, ordinal: ordinal + index + 1, kind: .person, payload: try CandidatePayload.encode(mention)))
        }
        return memory
    }

    /// The memory's links to people, with their origins.
    func personLinks(_ memory: MemoryID, relation: EntityRelation = .mention) throws -> [MomentEntity] {
        try store.entities.links(of: memory).filter { $0.entity.type == .person && $0.link.relation == relation }.map(\.link)
    }

    func person(_ link: MomentEntity) throws -> Person {
        try #require(try store.people.person(id: PersonID(rawValue: link.entityID.rawValue)))
    }

    /// The owner's answer stored with a waiting card, as the sheet (Task 5) will write it.
    func storeChoice(_ choice: String, saidName: String, person: PersonID? = nil, on candidate: CandidateID) throws {
        try db.writer.write { db in
            try db.execute(sql: "insert into candidate_person_choice (candidate_id, said_name, choice, person_id) values (?, ?, ?, ?)",
                           arguments: [candidate.rawValue, SaidName.key(saidName), choice, person?.rawValue])
        }
    }
}

@Test func aKnownBareNameIsLinkedAsAssumed() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let kept = try env.actions.acceptMemory(try env.card(people: ["Robin"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.entityID) == [robin.entityID])
    #expect(links.map(\.origin) == [.assumed], "a name alone is a guess and carries the mark")
    #expect(links.map(\.roleText) == ["Robin"])
    #expect(kept.newMentions.isEmpty)
}

@Test func keepDoesNotSaveARelationFromAGuess() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let kept = try env.actions.acceptMemory(try env.card(people: ["my roommate, Robin"]), joinStory: false)
    #expect(try env.personLinks(kept.memory.id).map(\.origin) == [.assumed])
    #expect(try env.store.people.aliases(of: robin.id).map(\.text) == ["Robin"], "a guess teaches the app no name")
}

@Test func nameWithAKnownRelationIsSaid() throws {
    let env = try Env()
    let sister = try env.store.people.insertPerson(displayName: "Danielle")
    try env.store.people.addAlias("my sister", to: sister.id)
    _ = try env.store.people.insertPerson(displayName: "Danielle")
    let kept = try env.actions.acceptMemory(try env.card(people: ["Danielle, my sister"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.entityID) == [sister.entityID])
    #expect(links.map(\.origin) == [.said])

    // The relation can also come from the person card of the same segment (plan decision 4).
    let again = try env.actions.acceptMemory(try env.card(people: ["Danielle"], mentions: [("Danielle", nil, "my sister")]), joinStory: false)
    #expect(try env.personLinks(again.memory.id).map(\.entityID) == [sister.entityID])
    #expect(try env.personLinks(again.memory.id).map(\.origin) == [.said])
}

@Test func anUnknownNameMakesAPersonMarkedNew() throws {
    let env = try Env()
    let kept = try env.actions.acceptMemory(try env.card(people: ["Tomas"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.origin) == [.new])
    let tomas = try env.person(try #require(links.first))
    #expect(tomas.displayName == "Tomas" && tomas.createdByGuess && tomas.nameOrigin == .said)
    #expect(try env.store.people.aliases(of: tomas.id).map(\.text) == ["Tomas"], "a new person's own name is their alias")
    #expect(try env.store.entities.entity(id: tomas.entityID)?.type == .person)
    #expect(kept.newMentions.isEmpty)
    #expect(try env.store.people.mentions(status: .unresolved).isEmpty, "no Who's this? for a name Keep made a person for")
}

@Test func aRelationAloneThatFitsNobodyNamesTheNewPerson() throws {
    let env = try Env()
    let kept = try env.actions.acceptMemory(try env.card(people: ["my roommate"]), joinStory: false)
    let person = try env.person(try #require(try env.personLinks(kept.memory.id).first))
    #expect(person.displayName == "my roommate")
}

@Test func aGroupPhraseStillMakesAMention() throws {
    let env = try Env()
    let before = try env.store.people.people().count
    let kept = try env.actions.acceptMemory(try env.card("our parents drove us to the lake", people: ["our parents"]), joinStory: false)
    #expect(kept.newMentions.map(\.text) == ["our parents"])
    #expect(try env.store.people.mentions(status: .unresolved).map(\.text) == ["our parents"])
    #expect(try env.personLinks(kept.memory.id).isEmpty)
    #expect(try env.store.people.people().count == before, "a phrase for several people makes no person")
}

@Test func theOwnersNameIsNeverACandidate() throws {
    let env = try Env()
    try env.store.profile.save(Profile(displayName: "Avery", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let owner = try #require(try env.store.profile.owner())
    let kept = try env.actions.acceptMemory(try env.card(people: ["Avery"]), joinStory: false)
    #expect(try env.personLinks(kept.memory.id).isEmpty, "the speaker is left out of their own story's people")
    #expect(try env.store.people.people().map(\.id) == [owner.id], "no second Avery")
    #expect(try !env.store.personLinks.known().contains { $0.id == owner.id })
}

@Test func onePersonNamedTwiceInOneCardIsOneLink() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    try env.store.people.addAlias("my roommate", to: robin.id)
    let kept = try env.actions.acceptMemory(try env.card(people: ["Robin", "my roommate, Robin"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.count == 1)
    #expect(links.first?.roleText == "Robin", "the first said name stays")
    #expect(links.first?.origin == .said, "the stronger origin of the two")
}

@Test func oneNewNameTwiceInOneCardIsOnePerson() throws {
    let env = try Env()
    let before = try env.store.people.people().count
    let kept = try env.actions.acceptMemory(try env.card(people: ["Tomas", "tomas", "my friend, Tomas"]), joinStory: false)
    #expect(try env.personLinks(kept.memory.id).count == 1)
    #expect(try env.store.people.people().count == before + 1)
}

@Test func aStoredChoiceWinsOverTheGuess() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let other = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let card = try env.card(people: ["Robin"])
    try env.storeChoice("person", saidName: " robin ", person: other.id, on: card.id)
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.entityID) == [other.entityID])
    #expect(links.map(\.origin) == [.confirmed])
}

@Test func aStoredNewChoiceMakesAPersonThatIsNotAGuess() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let card = try env.card(people: ["Robin"])
    try env.storeChoice("new", saidName: "Robin", on: card.id)
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    let link = try #require(try env.personLinks(kept.memory.id).first)
    #expect(link.entityID != robin.entityID && link.origin == .confirmed)
    let person = try env.person(link)
    #expect(person.displayName == "Robin" && !person.createdByGuess)
}

@Test func aStoredNotAPersonWritesNoLink() throws {
    let env = try Env()
    _ = try env.store.people.insertPerson(displayName: "Will")
    let card = try env.card(people: ["Will"])
    try env.storeChoice("not_a_person", saidName: "Will", on: card.id)
    let before = try env.store.people.people().count
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    #expect(try env.personLinks(kept.memory.id).isEmpty)
    #expect(kept.newMentions.isEmpty)
    #expect(try env.store.people.people().count == before)
}

@Test func aConfirmedChoiceSavesTheRelation() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let card = try env.card(people: ["my roommate, Robin"])
    try env.storeChoice("person", saidName: "my roommate, Robin", person: robin.id, on: card.id)
    _ = try env.actions.acceptMemory(card, joinStory: false)
    #expect(try env.store.people.aliases(of: robin.id).map(\.text).contains("my roommate"), "the owner's answer teaches the name")
}

@Test func choicesReadBackFromTheTable() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let card = try env.card(people: ["Robin", "Will", "Tomas"])
    try env.storeChoice("person", saidName: "Robin", person: robin.id, on: card.id)
    try env.storeChoice("not_a_person", saidName: "Will", on: card.id)
    try env.storeChoice("new", saidName: "Tomas", on: card.id)
    let choices = try env.store.personLinks.choices(for: card.id).sorted { $0.saidKey < $1.saidKey }
    #expect(choices == [PersonChoice(saidKey: "robin", choice: .person(robin.id), notAPerson: false),
                        PersonChoice(saidKey: "tomas", choice: .newPerson, notAPerson: false),
                        PersonChoice(saidKey: "will", choice: nil, notAPerson: true)])
}

@Test func knownReadsAliasesAndTheLatestLink() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    try env.store.people.addAlias("my roommate", to: robin.id)
    let never = try env.store.people.insertPerson(displayName: "Kira")
    let kept = try env.actions.acceptMemory(try env.card(people: ["Robin"]), joinStory: false)
    let known = try env.store.personLinks.known()
    let r = try #require(known.first { $0.id == robin.id })
    #expect(Set(r.aliases) == ["Robin", "my roommate"])
    #expect(r.lastLinked.map { abs($0.timeIntervalSince(kept.memory.createdAt)) < 1 } == true)
    #expect(known.first { $0.id == never.id }?.lastLinked == nil)
}

@Test func aRetellingDoesNotDowngradeAConfirmedLink() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let first = try env.card(people: ["Robin"])
    try env.storeChoice("person", saidName: "Robin", person: robin.id, on: first.id)
    let kept = try env.actions.acceptMemory(first, joinStory: false)
    #expect(try env.personLinks(kept.memory.id).map(\.origin) == [.confirmed])
    let retelling = try env.card(people: ["Robin"])
    _ = try env.actions.mergeCandidate(retelling, into: kept.memory.id)
    #expect(try env.personLinks(kept.memory.id).map(\.origin) == [.confirmed], "Same story never weakens what the owner chose")
}

@Test func aRetellingStrengthensAGuess() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    try env.store.people.addAlias("my roommate", to: robin.id)
    let kept = try env.actions.acceptMemory(try env.card(people: ["Robin"]), joinStory: false)
    #expect(try env.personLinks(kept.memory.id).map(\.origin) == [.assumed])
    _ = try env.actions.mergeCandidate(try env.card(people: ["Robin, my roommate"]), into: kept.memory.id)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.origin) == [.said], "the owner's own words in the retelling point to one person")
    #expect(links.map(\.roleText) == ["Robin"], "the first said name stays")
}

@Test func aFactAboutAGuessedPersonCarriesTheOrigin() throws {
    let env = try Env()
    let devon = try env.store.people.insertPerson(displayName: "Devon")
    let card = try env.card("Devon and I had our most formative years together", kind: .feeling, people: ["Devon"], about: "p1",
                            mentions: [("Devon", "p1", nil)])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    let details = try env.personLinks(kept.memory.id, relation: .detail)
    #expect(details.map(\.entityID) == [devon.entityID])
    #expect(details.map(\.origin) == [.assumed])
    #expect(try env.personLinks(kept.memory.id).map(\.origin) == [.assumed])
}

// I1 / R38: the model may put a person id from the packet in `about_ref`. That pick is still a guess.
@Test func aFactAboutAPacketPersonIDTakesTheMentionsOriginElseAssumed() throws {
    let env = try Env()
    let friend = try env.store.people.insertPerson(displayName: "Robin")
    let roommate = try env.store.people.insertPerson(displayName: "Robin")
    try env.store.people.addAlias("my roommate", to: roommate.id)

    let same = try env.actions.acceptMemory(try env.card("Robin is allergic to peanuts", kind: .fact, people: ["Robin, my roommate"],
                                                         about: roommate.id.rawValue), joinStory: false)
    #expect(try env.personLinks(same.memory.id).map(\.origin) == [.said])
    let sameDetail = try env.personLinks(same.memory.id, relation: .detail)
    #expect(sameDetail.map(\.entityID) == [roommate.entityID])
    #expect(sameDetail.map(\.origin) == [.said], "the mention reached the same person: the detail takes its origin")

    let other = try env.actions.acceptMemory(try env.card("Robin is allergic to peanuts", kind: .fact, people: ["Robin, my roommate"],
                                                          about: friend.id.rawValue), joinStory: false)
    let otherDetail = try env.personLinks(other.memory.id, relation: .detail)
    #expect(otherDetail.map(\.entityID) == [friend.entityID], "the model's pick stands, and it is marked")
    #expect(otherDetail.map(\.origin) == [.assumed])
}

@Test func aFactAboutTheOwnersIDHasNoOrigin() throws {
    let env = try Env()
    try env.store.profile.save(Profile(displayName: "Sam Ortega", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let owner = try #require(try env.store.profile.owner())
    let kept = try env.actions.acceptMemory(try env.card("I am allergic to peanuts", kind: .fact, people: [], about: owner.id.rawValue), joinStory: false)
    #expect(try env.personLinks(kept.memory.id, relation: .detail).map(\.origin) == [nil], "the owner is never a guess")
}

@Test func aFactAboutANewNameMakesOnePerson() throws {
    let env = try Env()
    let card = try env.card("Devon and I had our most formative years together", kind: .feeling, people: ["Devon"], about: "p1",
                            mentions: [("Devon", "p1", nil)])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    let detail = try #require(try env.personLinks(kept.memory.id, relation: .detail).first)
    #expect(detail.origin == .new)
    #expect(try env.personLinks(kept.memory.id).map(\.entityID) == [detail.entityID], "the mention and the detail are one new person")
    #expect(try env.store.people.people().filter { $0.displayName == "Devon" }.count == 1)
}

@Test func anAnswerStaysInItsRecording() throws {
    let env = try Env()
    // A name no memory carries: a person card waits in each of two recordings.
    let (_, first) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin called"])
    let (_, second) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin called again"])
    var mentions: [Mention] = []
    for segment in [first[0].id, second[0].id] {
        let out = MentionOut(text: "Robin", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9)
        let row = StoreFixtures.candidate(segment, kind: .person, payload: try CandidatePayload.encode(out))
        try env.store.candidates.insert(row)
        mentions.append(try env.actions.acceptMention(row))
    }
    _ = try env.actions.resolveMention(mentions[0].id, to: .new(displayName: "Robin"))
    #expect(try env.store.people.mention(id: mentions[1].id)?.status == .unresolved, "another recording's Robin is a new question")
}

@Test func anAnswerCarriesInsideItsRecording() throws {
    let env = try Env()
    let (_, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin called", "Robin called again"])
    var mentions: [Mention] = []
    for segment in segs.map(\.id) {
        let out = MentionOut(text: "Robin", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9)
        let row = StoreFixtures.candidate(segment, kind: .person, payload: try CandidatePayload.encode(out))
        try env.store.candidates.insert(row)
        mentions.append(try env.actions.acceptMention(row))
    }
    let robin = try #require(try env.actions.resolveMention(mentions[0].id, to: .new(displayName: "Robin")))
    #expect(try env.store.people.mention(id: mentions[1].id)?.personID == robin.id)
}

@Test func anAnswerLinksAsConfirmed() throws {
    let env = try Env()
    let (_, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["our parents drove us to the lake"])
    let card = try env.card(in: segs[0].id, "our parents drove us to the lake", people: ["our parents"])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    let mom = try env.store.people.insertPerson(displayName: "Mom")
    _ = try env.actions.resolveMention(try #require(kept.newMentions.first).id, to: .existing(mom.id))
    #expect(try env.personLinks(kept.memory.id).map(\.origin) == [.confirmed])
}

@Test func separatingATellingFindsItsPeopleByTheirLinks() throws {
    let env = try Env()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let kept = try env.actions.acceptMemory(try env.card(people: []), joinStory: false)
    let merged = try env.actions.mergeCandidate(try env.card(people: ["Robin"]), into: kept.memory.id)
    #expect(try env.personLinks(kept.memory.id).map(\.entityID) == [robin.entityID])
    let fresh = try env.actions.separateTelling(merged.receipt.target, order: 1)
    #expect(try env.personLinks(fresh.id).map(\.entityID) == [robin.entityID], "the telling takes the person it named")
    #expect(try env.personLinks(fresh.id).map(\.origin) == [.assumed], "the link keeps its origin when it moves")
    #expect(try env.personLinks(kept.memory.id).isEmpty)
}

// MARK: - Person cards left pending before Task 3

/// The waiting queue as the session screen builds it from the store.
private func waitingQueue(_ env: Env, session: SessionID) throws -> CardQueue {
    let candidates = env.store.candidates
    return CardQueue.waiting(pending: try candidates.pending(in: session), segmentMemories: { (try? candidates.candidates(for: $0)) ?? [] },
                             candidate: { try? candidates.fetch($0) })
}

@Test func keepClosesAPendingPersonCardItCarries() throws {
    let env = try Env()
    let (session, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin and our parents painted the fence"])
    // As extraction stored it before Task 3: each name a pending person card under its memory card.
    let card = try env.card(in: segs[0].id, "Robin and our parents painted the fence", people: ["Robin", "our parents"],
                            mentions: [("Robin", nil, nil), ("our parents", nil, nil)])
    let robinCard = try #require(try env.store.candidates.candidates(for: segs[0].id).first { CandidatePayload.mention($0)?.text == "Robin" })
    let groupCard = try #require(try env.store.candidates.candidates(for: segs[0].id).first { CandidatePayload.mention($0)?.text == "our parents" })
    var queue = try waitingQueue(env, session: session)

    _ = try env.actions.acceptMemory(card, joinStory: false)
    #expect(try env.store.candidates.fetch(robinCard.id)?.status == .accepted, "Keep linked Robin, so the card asks nothing")
    #expect(try env.store.candidates.fetch(groupCard.id)?.status == .pending, "a group phrase keeps its own question")

    // The screen keeps the card open, then rebuilds from the store: only the group's chip is left.
    queue.memoryAccepted(card.id.rawValue)
    var rebuilt = try waitingQueue(env, session: session)
    rebuilt.keepOpen(from: queue)
    let kept = rebuilt.cards.compactMap { if case .kept(let k) = $0 { k } else { nil } }
    #expect(kept.flatMap(\.followUps).map(\.id) == [groupCard.id.rawValue])
}

@Test func sameStoryClosesAPendingPersonCardItCarries() throws {
    let env = try Env()
    let kept = try env.actions.acceptMemory(try env.card(people: []), joinStory: false)
    let (_, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin painted the fence again"])
    let retelling = try env.card(in: segs[0].id, "Robin painted the fence again", people: ["Robin"], mentions: [("Robin", nil, nil)])
    let robinCard = try #require(try env.store.candidates.candidates(for: segs[0].id).first { $0.kind == .person })
    _ = try env.actions.mergeCandidate(retelling, into: kept.memory.id)
    #expect(try env.store.candidates.fetch(robinCard.id)?.status == .accepted)
    #expect(try env.personLinks(kept.memory.id).count == 1)
}

@Test func aFailedKeepLeavesThePersonCardPending() throws {
    let env = try Env()
    let (_, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin painted the fence"])
    let card = try env.card(in: segs[0].id, "Robin painted the fence", people: ["Robin"], mentions: [("Robin", nil, nil)])
    let robinCard = try #require(try env.store.candidates.candidates(for: segs[0].id).first { $0.kind == .person })
    // A kill at the person card's status write, the last step of Keep's one transaction.
    try env.db.writer.write { db in
        try db.execute(sql: """
            create trigger kill_keep before update of status on candidate when new.id = '\(robinCard.id.rawValue)'
            begin select raise(abort, 'killed'); end
            """)
    }
    #expect(throws: (any Error).self) { try env.actions.acceptMemory(card) }
    #expect(try env.store.candidates.fetch(robinCard.id)?.status == .pending, "a kill leaves the old state")
    #expect(try env.store.candidates.fetch(card.id)?.status == .pending)
    #expect(try env.store.memories.memory(createdFrom: card.id) == nil, "no kept memory behind a pending person card")
}

// MARK: - Extraction

private struct QueueEnv {
    let store: ExtractionStore, service: FakeExtractionService, session: SessionID, segments: [Segment]
    init(texts: [String], script: [Result<ExtractorOutput, ExtractionError>]) throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        (session, segments) = try StoreFixtures.session(in: store.sessions, segments: texts)
        service = FakeExtractionService(script)
    }
    func queue() -> ExtractionQueue { ExtractionQueue(session: session, service: service, store: store, log: { _ in }) }
}

@Test func aCarriedPersonNameShowsNoCard() async throws {
    let output = ExtractorOutput(
        memories: [MemoryOut(ref: "m1", title: "The fence", quote: "my roommate, Robin and I painted the fence", segmentSpan: WordSpan(startWord: 0, endWord: 7),
                             peopleRefs: ["my roommate, Robin"], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)],
        mentions: [MentionOut(text: "Robin", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8, relationText: "my roommate")], flags: .none)
    let env = try QueueEnv(texts: ["my roommate, Robin and I painted the fence"], script: [.success(output)])
    let queue = env.queue()
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    let rows = try env.store.candidates.candidates(for: env.segments[0].id)
    #expect(rows.first { $0.kind == .person }?.status == .accepted, "the kept card will carry the person")
    #expect(try env.store.candidates.pending(in: env.session).map(\.kind) == [.memory])
    #expect(try env.store.people.mentions(in: env.segments[0].id).isEmpty, "no Who's this? for a carried name")
}

@Test func aPersonNameNothingCarriesStillAsks() async throws {
    let output = ExtractorOutput(memories: [], mentions: [MentionOut(text: "Robin", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)], flags: .none)
    let env = try QueueEnv(texts: ["Robin called"], script: [.success(output)])
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let queue = env.queue()
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    let mentions = try env.store.people.mentions(in: env.segments[0].id)
    #expect(mentions.map(\.status) == [.unresolved], "a known name is still the owner's to answer")
    #expect(mentions.first?.personID == nil)
}

@Test func aNameOnlyAWithheldMemoryCarriesStillAsks() async throws {
    // After a serious disclosure the memory is withheld, so no Keep will ever link the name: it must not be lost.
    let output = ExtractorOutput(
        memories: [MemoryOut(ref: "m1", title: "The fence", quote: "Robin and I painted the fence", segmentSpan: WordSpan(startWord: 0, endWord: 5),
                             peopleRefs: ["Robin"], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)],
        mentions: [MentionOut(text: "Robin", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)],
        flags: Flags(seriousDisclosure: true, wantsToStop: false, wantsToChangeSubject: false))
    let env = try QueueEnv(texts: ["Robin and I painted the fence"], script: [.success(output)])
    let queue = env.queue()
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    #expect(try env.store.people.mentions(in: env.segments[0].id).map(\.status) == [.unresolved], "the name waits in the People queue")
}

// MARK: - Contacts (PC-b Task 2): rules 3 and 5 make a person linked to the one contact that fits

private func contact(_ id: String, _ fullName: String, nickname: String = "") -> PersonGuess.Contact {
    PersonGuess.Contact(identifier: id, fullName: fullName, givenName: String(fullName.split(separator: " ")[0]), nickname: nickname)
}
private let vale = contact("c-vale", "Robyn Vale")
private let hale = contact("c-hale", "Robyn Hale")

extension Env {
    func others() throws -> [Person] { try store.people.people().filter { !$0.isOwner } }
    func aliases(_ person: PersonID) throws -> [String] { try store.people.aliasesOldestFirst(of: person).map(\.text) }
}

@Test func oneContactAndNoPersonMakesAPersonLinkedToThatContact() throws {
    let env = try Env(contacts: [vale])
    let kept = try env.actions.acceptMemory(try env.card("Robyn and I painted the fence", people: ["Robyn"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.origin) == [.assumed], "rule 5 is a guess and carries the mark")
    let robyn = try env.person(try #require(links.first))
    #expect(robyn.displayName == "Robyn Vale" && robyn.nameOrigin == .contact && robyn.createdByGuess)
    #expect(robyn.contactIdentifier == "c-vale" && robyn.contactName == "Robyn Vale" && robyn.contactState == "linked")
    #expect(robyn.contactPhotoID == nil, "the picture is copied after Keep, not in its transaction")
    #expect(try env.aliases(robyn.id) == ["Robyn"], "the said name is the alias; the contact's name never is")
    #expect(try env.others().map(\.id) == [robyn.id])
    let link = try #require(try env.store.personLinks.links(to: robyn.id).first)
    #expect(link.personFromContact && link.saidName == "Robyn")
    #expect(kept.newMentions.isEmpty)
}

@Test func aFullerNameThatIsOneContactsFullNameLinksThatContact() throws {
    let env = try Env(contacts: [vale, hale])
    let kept = try env.actions.acceptMemory(try env.card("Robyn Vale painted the fence", people: ["Robyn Vale"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.origin) == [.assumed])
    let robyn = try env.person(try #require(links.first))
    #expect(robyn.contactIdentifier == "c-vale" && robyn.displayName == "Robyn Vale" && robyn.nameOrigin == .contact)
    #expect(try env.aliases(robyn.id) == ["Robyn Vale"], "the owner said the full name, so it is their words")
}

@Test func twoContactsThatFitMakeAPersonWithNoContact() throws {
    let env = try Env(contacts: [vale, contact("c-okafor", "Robyn Okafor")])
    let kept = try env.actions.acceptMemory(try env.card("Robyn painted the fence", people: ["Robyn"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.origin) == [.new], "rule 6: the app does not pick between two contacts")
    let robyn = try env.person(try #require(links.first))
    #expect(robyn.displayName == "Robyn" && robyn.nameOrigin == .said && robyn.createdByGuess)
    #expect(robyn.contactIdentifier == nil && robyn.contactName == nil && robyn.contactState == nil)
    #expect(try env.store.personLinks.links(to: robyn.id).first?.personFromContact == false)
}

// Review Focus 1: a person on file wins over a contact that also fits (rule 4), the most recently linked one.
@Test func aPersonOnFileWinsOverAContact() throws {
    let env = try Env(contacts: [contact("c-okafor", "Robin Okafor")])
    _ = try env.store.people.insertPerson(displayName: "Robin")
    let recent = try env.store.people.insertPerson(displayName: "Robin")
    let earlier = try env.card("Robin fixed the gate", people: ["Robin"])
    try env.storeChoice("person", saidName: "Robin", person: recent.id, on: earlier.id)
    _ = try env.actions.acceptMemory(earlier, joinStory: false)
    let before = try env.others().count

    let kept = try env.actions.acceptMemory(try env.card(people: ["Robin"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.entityID) == [recent.entityID])
    #expect(links.map(\.origin) == [.assumed])
    #expect(try env.others().count == before, "no person is made from the contact")
}

@Test func aContactAPersonHoldsIsNotASecondCandidate() throws {
    let env = try Env(contacts: [vale])
    let held = try env.store.people.insertPerson(displayName: "Bee")
    try env.db.writer.write { db in
        try db.execute(sql: "update person set contact_identifier = 'c-vale', contact_name = 'Robyn Vale', contact_state = 'linked' where id = ?",
                       arguments: [held.id.rawValue])
    }
    let kept = try env.actions.acceptMemory(try env.card("Robyn painted the fence", people: ["Robyn"]), joinStory: false)
    let links = try env.personLinks(kept.memory.id)
    #expect(links.map(\.entityID) == [held.entityID], "the contact counts as the person who holds it")
    #expect(links.map(\.origin) == [.assumed])
    #expect(try env.others().map(\.id) == [held.id])
}

@Test func oneCardThatNamesAContactTwiceMakesOnePerson() throws {
    let env = try Env(contacts: [vale, hale])
    let kept = try env.actions.acceptMemory(try env.card("Robyn Vale painted the fence", people: ["Robyn Vale", "robyn vale"]), joinStory: false)
    #expect(try env.personLinks(kept.memory.id).count == 1)
    #expect(try env.others().count == 1)
}

@Test func aSecondCardInTheRecordingReachesThePersonTheFirstMade() throws {
    let env = try Env(contacts: [vale])
    let (_, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robyn painted the fence", "Robyn fixed the gate"])
    let first = try env.card(in: segs[0].id, "Robyn painted the fence", people: ["Robyn"])
    let second = try env.card(in: segs[1].id, "Robyn fixed the gate", people: ["Robyn"])
    // Before Keep both waiting cards preview the contact, and nothing is written.
    #expect(try env.linkActions.preview(second).map(\.fromContact) == [true])
    #expect(try env.others().isEmpty)

    let a = try env.actions.acceptMemory(first, joinStory: false)
    let b = try env.actions.acceptMemory(second, joinStory: false)
    let robyn = try env.person(try #require(try env.personLinks(a.memory.id).first))
    #expect(try env.personLinks(b.memory.id).map(\.entityID) == [robyn.entityID], "the said name is now an alias of a person on file (rule 4)")
    #expect(try env.personLinks(b.memory.id).map(\.origin) == [.assumed])
    #expect(try env.others().map(\.id) == [robyn.id], "no second person")
    #expect(try env.aliases(robyn.id) == ["Robyn"])
}

@Test func thePreviewShowsTheChipKeepWrites() throws {
    let env = try Env(contacts: [vale])
    let card = try env.card("Robyn painted the fence", people: ["Robyn"])
    let tables = ["person", "entity", "moment_entity", "alias"]
    let counts = try tables.map { table in try env.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from \(table)") ?? 0 } }
    let chip = try #require(try env.linkActions.preview(card).first)
    #expect(chip == PreviewChip(saidName: "Robyn", name: "Robyn Vale", origin: .assumed, person: nil, fromContact: true))
    #expect(try tables.map { table in try env.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from \(table)") ?? 0 } } == counts,
            "the preview writes nothing")

    let kept = try env.actions.acceptMemory(card, joinStory: false)
    let person = try env.person(try #require(try env.personLinks(kept.memory.id).first))
    let link = try #require(try env.store.personLinks.links(to: person.id).first)
    #expect(link.person.displayName == chip.name && link.origin == chip.origin && link.personFromContact == chip.fromContact)
    #expect(PersonChipLine.text(origin: link.origin, saidName: link.saidName, fromContact: link.personFromContact, contacts: .someMatch)
            == PersonChipLine.text(origin: chip.origin, saidName: chip.saidName, fromContact: chip.fromContact, contacts: .someMatch))
    #expect(PersonChipLine.text(origin: chip.origin, saidName: chip.saidName, fromContact: chip.fromContact, contacts: .someMatch)
            == "Assumed \u{00B7} new, from your contacts")
    // Once the person is on file, a later card's preview names them and still reads as from the contacts.
    let later = try #require(try env.linkActions.preview(try env.card("Robyn fixed the gate", people: ["Robyn"])).first)
    #expect(later == PreviewChip(saidName: "Robyn", name: "Robyn Vale", origin: .assumed, person: person.id, fromContact: true))
}

// MARK: - The rule, in the sources

@Test func noExtractionPathCallsFindPerson() throws {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/LifelineKit")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)).compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }
    #expect(files.count > 50, "the walk found the kit's sources")
    // Only a name the owner typed or chose may be looked up by name.
    let typedNameCalls = ["findPersonOrOwner(matching: trimmed)", "findPersonOrOwner(matching: wanted)"]
    for file in files where !["PeopleRepository.swift", "EntityActions.swift"].contains(file.lastPathComponent) {
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { $0.contains("findPerson") }
        for line in lines {
            let allowed = file.lastPathComponent == "CandidateActions.swift" && typedNameCalls.contains { line.contains($0) }
            #expect(allowed, "\(file.lastPathComponent) looks a person up by name: \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
}
