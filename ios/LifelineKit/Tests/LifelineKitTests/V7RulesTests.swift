import Foundation
import Testing
@testable import LifelineKit

/// Extractor v7's rules that live in code (A2a): names that match by key, places with no name,
/// the owner's own name, and the stored title of a fact, feeling or goal.
private struct Env {
    let store: ExtractionStore, actions: CandidateActions
    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
    }

    /// A kept memory in a session of its own.
    func kept(_ text: String, kind: MemoryKind = .event, title: String? = nil, place: String? = nil) throws -> Memory {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        let words = text.split(separator: " ").count
        let out = MemoryOut(ref: "m1", kind: kind, title: title ?? "A title", quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                            peopleRefs: [], placeText: place, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return try actions.acceptMemory(c, joinStory: false).memory
    }
}

private let noFlags = Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: false)

private func fact(people: [String] = [], about: String? = nil) -> MemoryOut {
    MemoryOut(ref: "m1", kind: .fact, title: "", quote: "we were always close", segmentSpan: WordSpan(startWord: 0, endWord: 3),
              peopleRefs: people, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: about)
}

// MARK: - Names match by key

@Test func aPlaceIsFoundWhateverItsCaseOrEndPunctuation() throws {
    let env = try Env()
    let ohio = try env.store.entities.insert(type: .place, title: "Ohio")
    #expect(try env.store.entities.find(type: .place, title: "Ohio.")?.id == ohio.id)
    #expect(try env.store.entities.find(type: .place, title: "  ohio ")?.id == ohio.id)
    #expect(try env.store.entities.insert(type: .place, title: "Ohio.").id == ohio.id, "naming it again with a full stop makes no second place")
    #expect(try env.store.entities.entities(type: .place).count == 1)
}

@Test func differentSpellingsAndTypesStayApart() throws {
    let env = try Env()
    let place = try env.store.entities.insert(type: .place, title: "St. Louis")
    #expect(try env.store.entities.find(type: .place, title: "St Louis") == nil, "an inner full stop is part of the name")
    #expect(try env.store.entities.find(type: .thing, title: "St. Louis") == nil, "a thing is not found by a place's name")
    let thing = try env.store.entities.insert(type: .thing, title: "St. Louis")
    #expect(thing.id != place.id)
    #expect(try env.store.entities.find(type: .place, title: " ... ") == nil, "an empty key finds nothing")
}

@Test func theEarliestOfTwoPlacesWithOneKeyIsTheOneFound() throws {
    let env = try Env()
    // As the old comparison left them: two rows for one place.
    let first = Entity(type: .place, title: "Ohio"), second = Entity(type: .place, title: "Ohio.")
    try env.store.entities.apply({ var w = EntityRepository.Write(); w.entities = [first, second]; return w }())
    #expect(try env.store.entities.find(type: .place, title: "ohio")?.id == first.id)
}

@Test func aCollectionIsReusedByKey() throws {
    let env = try Env()
    let trips = try env.store.chapters.insertCollection(titled: "Family trips")
    #expect(try env.store.chapters.insertCollection(titled: "family trips.").id == trips.id)
    #expect(try env.store.chapters.insertCollection(titled: "Family trip").id != trips.id)
    #expect(try env.store.chapters.collections().count == 2)
}

// MARK: - A place with no name

@Test func genericPhrasesAreThoseThatStartWithAnIndefiniteWord() {
    for text in ["a restaurant", "An old barn", "some town", "somewhere up north", "  a   café "] { #expect(GenericPhrase.isGeneric(text), "\(text)") }
    for text in ["our house", "Alder Street", "the restaurant", "Andover", "my grandmother's kitchen", "", "   "] { #expect(!GenericPhrase.isGeneric(text), "\(text)") }
}

@Test func aNameThatStartsLikeAnArticleIsNotGeneric() {
    for text in ["A Coruña", "An Loc", "a restaurant in Boston", "Some Like It Hot Diner"] { #expect(!GenericPhrase.isGeneric(text), "\(text)") }
    #expect(GenericPhrase.isGeneric("A restaurant"), "a capital on the first word alone is the start of a sentence")
}

@Test func aKeptMemoryWithAGenericPlaceMakesNoPlace() throws {
    let env = try Env()
    let memory = try env.kept("we ate at a restaurant by the road", place: "a restaurant")
    #expect(try env.store.memories.places(of: memory.id).isEmpty)
    #expect(try env.store.entities.entities(type: .place).isEmpty, "the phrase stays in the quote and makes no place")
    #expect(memory.summaryQuote.contains("a restaurant"))
}

@Test func aKeptMemoryWithANamedPlaceStillMakesOne() throws {
    let env = try Env()
    let memory = try env.kept("we lived on Alder Street then", place: "Alder Street")
    #expect(try env.store.memories.places(of: memory.id).count == 1)
    #expect(try env.store.entities.entities(type: .place).map(\.title) == ["Alder Street"])
}

// MARK: - The owner's own name

@Test func ownerNamesMatchByKeyAndNeverWithARelation() {
    let names = OwnerNames(names: ["Jordan", "Jordy", ""])
    #expect(names.isOwner("jordan") && names.isOwner("Jordan.") && names.isOwner("JORDY"))
    #expect(!names.isOwner("Jordan", relation: "my cousin"), "someone else who shares the name")
    #expect(names.isOwner("Jordan", relation: "  "), "an empty relation is no relation")
    #expect(!names.isOwner("Maya") && !names.isOwner(""))
    #expect(!OwnerNames(names: [""]).isOwner(""), "an owner with no typed name matches nobody")
}

@Test func theOwnersNameLeavesTheOutputAndAFactAboutItIsAboutSelf() {
    let names = OwnerNames(names: ["Jordan"])
    let me = MentionOut(text: "Jordan", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, ref: "p1")
    let cousin = MentionOut(text: "Jordan", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, relationText: "my cousin", ref: "p2")
    let maya = MentionOut(text: "Maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, ref: "p3")
    let place = MentionOut(text: "Jordan", kind: .place, likelyAliasOfPersonID: nil, confidence: 0.9, ref: "t1")
    let validated = OutputValidator.Validated(
        accepted: [.mention(me), .mention(cousin), .mention(maya), .mention(place),
                   .memory(fact(people: ["Jordan", "Maya"], about: "p1")), .memory(fact(about: "p3"))],
        rejected: [], flags: noFlags)
    let out = names.removingOwner(from: validated)
    #expect(out.accepted == [.mention(cousin), .mention(maya), .mention(place),
                             .memory(fact(people: ["Maya"], about: "self")), .memory(fact(about: "p3"))])
    #expect(out.flags == noFlags && out.rejected.isEmpty)
}

@Test func withNoOwnerNameTheOutputIsUnchanged() {
    let me = MentionOut(text: "Jordan", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9, ref: "p1")
    let validated = OutputValidator.Validated(accepted: [.mention(me), .memory(fact(people: ["Jordan"], about: "p1"))], rejected: [], flags: noFlags)
    #expect(OwnerNames(names: []).removingOwner(from: validated) == validated)
}

@Test func thePersonLookupNeverReturnsTheOwner() throws {
    let env = try Env()
    try env.store.profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    #expect(try env.store.people.findPerson(matching: "Jordan") == nil, "the owner is the speaker, not someone a story mentions")
    #expect(try env.store.people.ownerNames().isOwner("jordan"))
    let cousin = try env.store.people.insertPerson(displayName: "Jordan")
    #expect(try env.store.people.findPerson(matching: "Jordan")?.id == cousin.id, "another person with the name is still found")
}

@Test func thatsMeAddsANameForTheOwner() throws {
    let env = try Env()
    try env.store.people.addOwnerAlias("Jordy")
    #expect(try env.store.people.ownerNames().keys.isEmpty, "with no owner nothing is written")
    try env.store.profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    try env.store.people.addOwnerAlias("Jordy")
    let names = try env.store.people.ownerNames()
    #expect(names.isOwner("Jordy") && names.isOwner("Jordan"))
    #expect(try env.store.people.findPerson(matching: "Jordy") == nil, "and it never names another person")
}

@Test func typingYourOwnNameLinksYouAndMakesNoSecondPerson() throws {
    let env = try Env()
    try env.store.profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let owner = try #require(try env.store.profile.owner())
    let memory = try env.kept("we built the tree house that summer")
    let linked = try env.actions.linkNewPerson(named: " jordan ", to: memory.id)
    #expect(linked.id == owner.id, "the owner, not a new person with the owner's name")
    #expect(try env.store.people.people().count == 1)
    #expect(try env.store.people.findPersonOrOwner(matching: "Maya") == nil, "an unknown name is still nobody")
    let maya = try env.actions.linkNewPerson(named: "Maya", to: memory.id)
    #expect(try env.store.people.findPersonOrOwner(matching: "maya")?.id == maya.id)
}

@Test func keepingAnOldCardThatNamesTheOwnerAsksNothingAndMakesNoPerson() throws {
    let env = try Env()
    try env.store.profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let text = "Jordan and Maya built the tree house"
    let (_, segs) = try StoreFixtures.session(in: env.store.sessions, segments: [text])
    // As extractor v6 stored it, before the filter: the owner's name among the people.
    let out = MemoryOut(ref: "m1", kind: .event, title: "The tree house", quote: text, segmentSpan: WordSpan(startWord: 0, endWord: 6),
                        peopleRefs: ["Jordan", "Maya"], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
    let card = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
    try env.store.candidates.insert(card)
    let kept = try env.actions.acceptMemory(card, joinStory: false)
    // Task 3: Maya, whom the app does not know, becomes a person marked new; the owner's name makes nobody.
    #expect(kept.newMentions.isEmpty)
    #expect(try env.store.memories.people(of: kept.memory.id).map(\.displayName) == ["Maya"])
    #expect(try env.store.people.people().filter { $0.displayName == "Jordan" }.count == 1, "no second person with the owner's name")
}

// MARK: - The stored title of a fact, feeling or goal

@Test func theStoredTitleIsTheStartOfTheCleanedQuote() {
    #expect(MemoryLabel.storedTitle(quote: "I think we had some of our most formative experiences together") == "I think we had some of our most…")
    #expect(MemoryLabel.storedTitle(quote: "um, he lived next door") == "He lived next door")
    #expect(MemoryLabel.storedTitle(quote: "close") == "Close")
    #expect(MemoryLabel.storedTitle(quote: "  ") == "")
}

@Test func aKeptFeelingStoresItsQuoteNotAMadeUpTitle() throws {
    let env = try Env()
    let feeling = try env.kept("I think we had some of our most formative experiences together", kind: .feeling, title: "our most formative experiences together")
    #expect(feeling.title == "I think we had some of our most…")
    #expect(MemoryLabel.heading(for: feeling) == "“I think we had some of our most formative experiences together”")
    let fact = try env.kept("he lived next door", kind: .fact, title: "")
    #expect(fact.title == "He lived next door", "an empty title from the model is fine for a fact")
}

@Test func aKeptMomentKeepsItsTitle() throws {
    let env = try Env()
    let moment = try env.kept("we built the tree house that summer", kind: .event, title: "The tree house")
    #expect(moment.title == "The tree house" && MemoryLabel.heading(for: moment) == "The tree house")
    let other = try env.kept("something about the yard", kind: .other, title: "The yard")
    #expect(other.title == "The yard", "an unsorted memory is treated as a moment")
}
