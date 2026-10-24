import Foundation
import Testing
@testable import LifelineKit

private struct Env {
    let store: ExtractionStore, actions: CandidateActions, session: SessionID, segment: Segment, words: [Word]
    init(text: String = "the garden had a pomegranate tree and my mother picked them in Fresno") throws {
        let db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = CandidateActions(store: store)
        (session, _) = try StoreFixtures.session(in: store.sessions, segments: [text])
        segment = try store.sessions.segments(in: session)[0]
        words = try store.sessions.words(in: segment.id)
    }

    func memoryCandidate(people: [String] = ["my mother"], place: String? = nil, anchors: [AnchorOut] = [], span: WordSpan = WordSpan(startWord: 1, endWord: 3), ordinal: Int = 0) throws -> Candidate {
        let out = MemoryOut(ref: "m1", title: "The pomegranate tree", quote: "garden had a", segmentSpan: span, peopleRefs: people, placeText: place,
                            anchors: anchors, collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segment.id, ordinal: ordinal, kind: .memory, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return c
    }

    func mentionCandidate(_ text: String = "my mother", ordinal: Int = 1, relation: String? = nil) throws -> Candidate {
        let out = MentionOut(text: text, kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8, relationText: relation)
        let c = StoreFixtures.candidate(segment.id, ordinal: ordinal, kind: .person, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return c
    }
}

@Test func acceptMemoryWritesSpanInMillisecondsFromWords() throws {
    let env = try Env()
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: []))
    let spans = try env.store.memories.spans(of: accepted.memory.id)
    #expect(spans.count == 1 && spans[0].startMs == env.words[1].startMs && spans[0].endMs == env.words[3].endMs && spans[0].order == 0)
    #expect(accepted.memory.summaryQuote == "garden had a" && accepted.memory.title == "The pomegranate tree" && accepted.memory.isUnplaced)
    #expect(try env.store.candidates.fetch(try #require(accepted.memory.createdFromCandidateID))?.status == .accepted)
}

@Test func peopleRefMatchingAnAliasLinksWithoutAMention() throws {
    let env = try Env()
    let mom = try env.store.people.insertPerson(displayName: "Rosa")
    try env.store.people.addAlias("my mother", to: mom.id)
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: ["My Mother"]))
    #expect(accepted.newMentions.isEmpty)
    #expect(try env.store.memories.people(of: accepted.memory.id).map(\.id) == [mom.id])
    #expect(try env.store.people.mentions(status: .unresolved).isEmpty)
}

@Test func unknownPeopleRefBecomesOneMention() throws {
    let env = try Env()
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: ["my mother"]))
    #expect(accepted.newMentions.map(\.text) == ["my mother"])
    #expect(try env.store.people.mentions(status: .unresolved).count == 1)
    #expect(try env.store.memories.people(of: accepted.memory.id).isEmpty)
}

@Test func samePersonTwiceInOneSegmentLinksOnce() throws {
    let env = try Env()
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: ["my mother", "My mother"]))
    #expect(accepted.newMentions.count == 1)
    let person = try #require(try env.actions.resolveMention(accepted.newMentions[0].id, to: .new(displayName: "Rosa")))
    #expect(person.displayName == "Rosa")
    #expect(try env.store.memories.people(of: accepted.memory.id).map(\.displayName) == ["Rosa"])
    #expect(try env.store.people.aliases(of: person.id).map(\.text).sorted() == ["Rosa", "my mother"])
}

@Test func resolveExistingPersonLinksTheMemory() throws {
    let env = try Env()
    let rosa = try env.store.people.insertPerson(displayName: "Rosa")
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate())
    _ = try env.actions.resolveMention(accepted.newMentions[0].id, to: .existing(rosa.id))
    #expect(try env.store.memories.people(of: accepted.memory.id).map(\.id) == [rosa.id])
    #expect(try env.store.people.mention(id: accepted.newMentions[0].id)?.status == .resolved)
}

@Test func notAPersonLinksNothing() throws {
    let env = try Env()
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate())
    #expect(try env.actions.resolveMention(accepted.newMentions[0].id, to: .notAPerson) == nil)
    #expect(try env.store.memories.people(of: accepted.memory.id).isEmpty)
    #expect(try env.store.people.mention(id: accepted.newMentions[0].id)?.status == .notAPerson)
}

@Test func acceptTwiceIsRejected() throws {
    let env = try Env()
    let candidate = try env.memoryCandidate(people: [])
    _ = try env.actions.acceptMemory(candidate)
    #expect(throws: CandidateActions.Error.notPending) { try env.actions.acceptMemory(candidate) }
    #expect(try env.store.memories.memories(in: env.session).count == 1)
}

@Test func dismissMarksTheCandidate() throws {
    let env = try Env()
    let candidate = try env.memoryCandidate(people: [])
    try env.actions.dismiss(candidate)
    #expect(try env.store.candidates.fetch(candidate.id)?.status == .dismissed)
    #expect(throws: CandidateActions.Error.notPending) { try env.actions.acceptMemory(candidate) }
}

@Test func placeTextCreatesPlaceAndLink() throws {
    let env = try Env()
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: [], place: "Fresno"))
    #expect(try env.store.memories.places(of: accepted.memory.id).map(\.nameText) == ["Fresno"])
}

@Test func anchorsAreStoredUnresolved() throws {
    let env = try Env()
    let anchor = AnchorOut(phrase: "when I was six", relation: .age, targetText: nil, value: "6")
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: [], anchors: [anchor]))
    let stored = try env.store.memories.anchors(of: accepted.memory.id)
    #expect(stored.count == 1 && stored[0].phrase == "when I was six" && stored[0].relation == .age && !stored[0].resolved && stored[0].targetKind == .none)
}

@Test func acceptMentionCreatesTheMentionRowOnce() throws {
    let env = try Env()
    let candidate = try env.mentionCandidate("my mother")
    let mention = try env.actions.acceptMention(candidate)
    #expect(mention.text == "my mother" && mention.status == .unresolved)
    #expect(try env.store.candidates.fetch(candidate.id)?.status == .accepted)
    let again = try env.actions.acceptMention(candidate)
    #expect(again.id == mention.id)
    #expect(try env.store.people.mentions(status: .unresolved).count == 1)
}

@Test func resolvingAMentionCandidateLinksMemoriesFromTheSameSegment() throws {
    let env = try Env()
    let memory = try env.actions.acceptMemory(try env.memoryCandidate(people: ["my mother"], ordinal: 0))
    // The memory already queued "my mother"; the mention card for the same name reuses that row.
    let mention = try env.actions.acceptMention(try env.mentionCandidate("my mother", ordinal: 1))
    #expect(mention.id == memory.newMentions[0].id)
    _ = try env.actions.resolveMention(mention.id, to: .new(displayName: "Rosa"))
    #expect(try env.store.memories.people(of: memory.memory.id).map(\.displayName) == ["Rosa"])
}

@Test func wrongKindIsRejected() throws {
    let env = try Env()
    let mention = try env.mentionCandidate()
    #expect(throws: CandidateActions.Error.wrongKind) { try env.actions.acceptMemory(mention) }
    let memory = try env.memoryCandidate(people: [])
    #expect(throws: CandidateActions.Error.wrongKind) { try env.actions.acceptMention(memory) }
}

@Test func resolveNewReusesAKnownPerson() throws {
    let env = try Env()
    let rosa = try env.store.people.insertPerson(displayName: "Rosa")
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: ["my mother"]))
    let person = try #require(try env.actions.resolveMention(accepted.newMentions[0].id, to: .new(displayName: "rosa ")))
    #expect(person.id == rosa.id, "typing a name the app knows must not make a second person")
    #expect(try env.store.people.people().filter { !$0.isOwner }.count == 1)
}

@Test func resolvingOneMentionResolvesTheSameNameEverywhere() throws {
    let env = try Env()
    let other = try StoreFixtures.session(in: env.store.sessions, segments: ["my mother sang"])
    let later = Mention(id: .init(), segmentID: other.1[0].id, text: "My Mother", status: .unresolved, personID: nil)
    try env.store.people.insertMention(later)
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: ["my mother"]))
    let rosa = try #require(try env.actions.resolveMention(accepted.newMentions[0].id, to: .new(displayName: "Rosa")))
    #expect(try env.store.people.mention(id: later.id)?.personID == rosa.id)
    #expect(try env.store.people.mentions(status: .unresolved).isEmpty)
}

@Test func acceptMemoryWritesMemoryAndCandidateStatusTogether() throws {
    let env = try Env()
    // A span the words cannot satisfy fails inside the write; the candidate must stay pending.
    let candidate = try env.memoryCandidate(people: [], span: WordSpan(startWord: 0, endWord: 99))
    #expect(throws: CandidateActions.Error.emptySpan) { try env.actions.acceptMemory(candidate) }
    #expect(try env.store.candidates.fetch(candidate.id)?.status == .pending)
    #expect(try env.store.memories.memories(in: env.session).isEmpty)
}

@Test func resolvingAMentionSavesTheKinPhraseAsAnAlias() throws {
    let env = try Env(text: "my mom Marcel made dinner")
    let mention = try env.actions.acceptMention(try env.mentionCandidate("Marcel", relation: "my mom"))
    #expect(mention.relationText == "my mom")
    let person = try #require(try env.actions.resolveMention(mention.id, to: .new(displayName: "Marcelle")))
    #expect(try env.store.people.aliases(of: person.id).map(\.text).sorted() == ["Marcel", "Marcelle", "my mom"])
    #expect(try env.store.people.findPerson(matching: "my mom")?.id == person.id)
}

@Test func peopleRefWithRoleAndNameMatchesTheNamedPerson() throws {
    let env = try Env(text: "the garden had a pomegranate tree and my mom, Marcel, picked them")
    let marcel = try env.store.people.insertPerson(displayName: "Marcel")
    let accepted = try env.actions.acceptMemory(try env.memoryCandidate(people: ["my mom, Marcel"]))
    #expect(accepted.newMentions.isEmpty)
    #expect(try env.store.memories.people(of: accepted.memory.id).map(\.id) == [marcel.id])
    #expect(try env.store.people.aliases(of: marcel.id).map(\.text).contains("my mom"), "the role phrase becomes an alias")
}

@Test func dismissedCandidatesAndNotAPersonMentionsCanBeRestored() throws {
    let env = try Env()
    let memory = try env.memoryCandidate(people: [])
    try env.actions.dismiss(memory)
    #expect(try env.store.candidates.dismissed(in: env.session).map(\.id) == [memory.id])
    try env.actions.restore(memory)
    #expect(try env.store.candidates.fetch(memory.id)?.status == .pending)
    #expect(try env.store.candidates.dismissed(in: env.session).isEmpty)
    #expect(throws: CandidateActions.Error.notDismissed) { try env.actions.restore(memory) }

    let mentionCandidate = try env.mentionCandidate("Mr. Spitzig")
    let mention = try env.actions.acceptMention(mentionCandidate)
    _ = try env.actions.resolveMention(mention.id, to: .notAPerson)
    #expect(try env.store.people.mention(id: mention.id)?.status == .notAPerson)
    try env.actions.restoreMention(mention.id)
    #expect(try env.store.people.mention(id: mention.id)?.status == .unresolved)
}

@Test func withheldAndInventedCandidatesAreNotRestorable() throws {
    let env = try Env()
    let invented = try env.memoryCandidate(people: [])
    try env.store.candidates.setStatus(invented.id, .dismissed, rejection: "quote not in segment")
    #expect(try env.store.candidates.dismissed(in: env.session).isEmpty, "only what the owner dismissed is offered back")
    #expect(throws: CandidateActions.Error.notDismissed) { try env.actions.restore(invented) }
}
