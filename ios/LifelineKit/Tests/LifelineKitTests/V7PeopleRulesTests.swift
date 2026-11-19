import Foundation
import Testing
@testable import LifelineKit

/// Extractor v7's rules about people that live in code (A2a): what a fact is about once its
/// person is named, and phrases for several people.
private struct Env {
    let db: AppDatabase, store: ExtractionStore, actions: CandidateActions
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = CandidateActions(store: store)
    }

    /// The person card of the card's segment that says `text`.
    func personCard(_ text: String, of card: Candidate) throws -> Candidate {
        try #require(try store.candidates.candidates(for: card.segmentID).first { $0.kind == .person && CandidatePayload.mention($0)?.text == text })
    }

    /// One segment with a memory card, and a person card for each `(name, ref)` the extractor found.
    func card(_ text: String, kind: MemoryKind, people: [String] = [], about: String? = nil, mentions: [(String, String)] = []) throws -> Candidate {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        let words = text.split(separator: " ").count
        let out = MemoryOut(ref: "m1", kind: kind, title: "A title", quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                            peopleRefs: people, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: about)
        let memory = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(memory)
        for (index, (name, ref)) in mentions.enumerated() {
            let mention = MentionOut(text: name, kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, ref: ref)
            try store.candidates.insert(StoreFixtures.candidate(segs[0].id, ordinal: index + 1, kind: .person, payload: try CandidatePayload.encode(mention)))
        }
        return memory
    }
}

private let noFlags = Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: false)

private func fact(about: String?) -> MemoryOut {
    MemoryOut(ref: "m1", kind: .fact, title: "", quote: "we were always close", segmentSpan: WordSpan(startWord: 0, endWord: 3),
              peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: about)
}

// MARK: - about_ref names something real

@Test func anAboutRefThatNamesNothingIsClearedAndTheMemoryStays() {
    let mention = MentionOut(text: "Devon", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, ref: "p1")
    let validated = OutputValidator.Validated(
        accepted: [.mention(mention), .memory(fact(about: "self")), .memory(fact(about: "e-known")), .memory(fact(about: "p1")),
                   .memory(fact(about: "made-up-id")), .memory(fact(about: nil))],
        rejected: [], flags: noFlags)
    let out = AboutRefCheck.cleared(validated, knownIDs: ["e-known"])
    #expect(out.accepted == [.mention(mention), .memory(fact(about: "self")), .memory(fact(about: "e-known")), .memory(fact(about: "p1")),
                             .memory(fact(about: nil)), .memory(fact(about: nil))])
    #expect(out.accepted.count == validated.accepted.count, "no memory is dropped for a bad about_ref")
}

// MARK: - A fact about a person

@Test func aFactAboutAKnownNameIsTheirDetailAtKeep() throws {
    let env = try Env()
    let devon = try env.store.people.insertPerson(displayName: "Devon")
    let card = try env.card("Devon and I had our most formative years together", kind: .feeling, people: ["Devon"], about: "p1", mentions: [("Devon", "p1")])
    let memory = try env.actions.acceptMemory(card, joinStory: false).memory
    #expect(try env.store.entities.details(of: devon.entityID).map(\.id) == [memory.id])
    #expect(try env.store.entities.links(of: memory.id).filter { $0.link.relation == .detail }.map(\.link.origin) == [.assumed], "Task 3: a guess, marked")
}

// Task 3: Keep makes the person for a name it does not know, so the feeling is their detail at once.
@Test func aFactAboutANewNameIsTheNewPersonsDetailAtKeep() throws {
    let env = try Env()
    let card = try env.card("Devon and I had our most formative years together", kind: .feeling, people: ["Devon"], about: "p1", mentions: [("Devon", "p1")])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    #expect(kept.newMentions.isEmpty)
    let devon = try #require(try env.store.memories.people(of: kept.memory.id).first)
    #expect(devon.displayName == "Devon" && devon.createdByGuess)
    #expect(try env.store.entities.details(of: devon.entityID).map(\.id) == [kept.memory.id], "the feeling is on Devon's page")
}

@Test func aMomentNeverBecomesADetailAndNotAPersonLinksNothing() throws {
    let env = try Env()
    let moment = try env.card("Devon and I drove to the coast", kind: .event, people: ["Devon"], about: "p1", mentions: [("Devon", "p1")])
    let keptMoment = try env.actions.acceptMemory(moment, joinStory: false)
    let devon = try #require(try env.store.memories.people(of: keptMoment.memory.id).first)
    #expect(try env.store.entities.details(of: devon.entityID).isEmpty, "a moment mentions a person; it is not a detail of them")

    // Task 3: "not a person" is answered on the card before Keep (the sheet stores it), not after.
    let feeling = try env.card("Rover was the best of us", kind: .feeling, people: ["Rover"], about: "p1", mentions: [("Rover", "p1")])
    try env.db.writer.write { db in
        try db.execute(sql: "insert into candidate_person_choice (candidate_id, said_name, choice) values (?, 'rover', 'not_a_person')", arguments: [feeling.id.rawValue])
    }
    let keptFeeling = try env.actions.acceptMemory(feeling, joinStory: false)
    #expect(try !env.store.entities.hasDetail(keptFeeling.memory.id))
    #expect(try env.store.memories.people(of: keptFeeling.memory.id).isEmpty)
}

// Task 3: only a group phrase still waits for an answer after Keep, so the hand-placed detail is shown on one.
@Test func aDetailThePersonAlreadyPlacedIsNotMoved() throws {
    let env = try Env()
    let maya = try env.store.people.insertPerson(displayName: "Maya")
    let dad = try env.store.people.insertPerson(displayName: "Dad")
    let card = try env.card("our parents were always close to us", kind: .feeling, people: ["our parents"], about: "p1", mentions: [("our parents", "p1")])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    #expect(try !env.store.entities.hasDetail(kept.memory.id), "a phrase for several people is nobody's detail yet")
    try env.store.entities.moveDetail(kept.memory.id, to: maya.entityID)
    let mention = try #require(kept.newMentions.first)
    _ = try env.actions.resolveMention(mention.id, to: .existing(dad.id))
    #expect(try env.store.entities.details(of: maya.entityID).map(\.id) == [kept.memory.id], "the link the person chose stays")
    #expect(try env.store.entities.details(of: dad.entityID).isEmpty)
}

// MARK: - A phrase for several people

@Test func groupPhrasesEndInAPluralKinWord() {
    for text in ["our parents", "my grandparents", "the kids", "Parents", "my folks", "our cousins.", "my parents'"] { #expect(GroupPhrase.isGroup(text), "\(text)") }
    for text in ["my parent", "Mom and Dad", "Maya", "my sister", "the Parents Association dinner", "", "  "] { #expect(!GroupPhrase.isGroup(text), "\(text)") }
}

@Test func aGroupAnsweredWithSeveralPeopleLinksThemAllAndSavesNoName() throws {
    let env = try Env()
    let mom = try env.store.people.insertPerson(displayName: "Mom"), dad = try env.store.people.insertPerson(displayName: "Dad")
    let card = try env.card("our parents drove us to the lake", kind: .event, people: ["our parents"])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    let mention = try #require(kept.newMentions.first)
    #expect(mention.text == "our parents")
    try env.actions.resolveGroup(mention.id, people: [mom.id, dad.id])
    #expect(Set(try env.store.memories.people(of: kept.memory.id).map(\.id)) == Set([mom.id, dad.id]))
    #expect(try env.store.people.findPerson(matching: "our parents") == nil, "the phrase is nobody's name")
    #expect(try env.store.people.mention(id: mention.id)?.status == .resolved)
    #expect(try env.store.people.mentions(status: .unresolved).isEmpty, "it is not asked about again")
}

@Test func leaveItAsSaidLinksNobody() throws {
    let env = try Env()
    let card = try env.card("our parents drove us to the lake", kind: .event, people: ["our parents"])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    try env.actions.leaveGroupAsSaid(try #require(kept.newMentions.first).id)
    #expect(try env.store.memories.people(of: kept.memory.id).isEmpty)
    #expect(try env.store.people.mentions(status: .unresolved).isEmpty)
}

@Test func aGroupPhraseAnsweredWithOnePersonIsStillNotTheirName() throws {
    let env = try Env()
    let dad = try env.store.people.insertPerson(displayName: "Dad")
    let first = try env.card("our parents drove us to the lake", kind: .event, people: ["our parents"])
    let keptFirst = try env.actions.acceptMemory(first, joinStory: false)
    _ = try env.actions.resolveMention(try #require(keptFirst.newMentions.first).id, to: .existing(dad.id))
    #expect(try env.store.memories.people(of: keptFirst.memory.id).map(\.id) == [dad.id], "this memory is linked as the person said")
    #expect(try !env.store.people.aliases(of: dad.id).map(\.text).contains("our parents"))
    // The same phrase in a later story is a new question.
    let second = try env.card("our parents met at a dance", kind: .event, people: ["our parents"])
    let keptSecond = try env.actions.acceptMemory(second, joinStory: false)
    #expect(keptSecond.newMentions.map(\.text) == ["our parents"], "it asks again")
    #expect(try env.store.memories.people(of: keptSecond.memory.id).isEmpty)
}

// Task 3: the question now comes from a person card that no memory carries; Keep no longer asks.
@Test func aNameStillBecomesAnAlias() throws {
    let env = try Env()
    let maya = try env.store.people.insertPerson(displayName: "Maya")
    let card = try env.card("my sister climbed the tree", kind: .event, people: [], mentions: [("my sister", "p1")])
    let mention = try env.actions.acceptMention(try env.personCard("my sister", of: card))
    _ = try env.actions.resolveMention(mention.id, to: .existing(maya.id))
    #expect(try env.store.people.findPerson(matching: "my sister")?.id == maya.id, "one person's relation is still learned")
}

@Test func removingANameKeepsEveryLinkAndStopsLaterMatches() throws {
    let env = try Env()
    let dad = try env.store.people.insertPerson(displayName: "Dad")
    try env.store.people.addAlias("our parents", to: dad.id)   // as the old code saved it
    let card = try env.card("our parents drove us to the lake", kind: .event, people: ["our parents"])
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    // Task 3: a group phrase is never looked up, so the old alias no longer links it silently; it asks.
    #expect(try env.store.memories.people(of: kept.memory.id).isEmpty)
    try env.actions.resolveGroup(try #require(kept.newMentions.first).id, people: [dad.id])
    #expect(try env.store.memories.people(of: kept.memory.id).map(\.id) == [dad.id])
    try env.store.people.removeAlias(" Our Parents ", from: dad.id)
    #expect(try env.store.memories.people(of: kept.memory.id).map(\.id) == [dad.id], "removing a name changes no memory")
    #expect(try env.store.people.findPerson(matching: "our parents") == nil)
    #expect(try env.store.people.findPerson(matching: "Dad")?.id == dad.id, "their own name is untouched")
}
