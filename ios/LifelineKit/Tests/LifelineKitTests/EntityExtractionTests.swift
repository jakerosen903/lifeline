import Foundation
import Testing
@testable import LifelineKit

// M7, PR B: extractor v6, Keep links entities, entity cards, ideas titled in the person's words.

private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
private let oct25 = DateComponents(calendar: utc, timeZone: utc.timeZone, year: 2026, month: 10, day: 25, hour: 12).date!

@Test func v6DecodesEntityRefsAndAboutRef() throws {
    let json = """
    {"memories":[{"ref":"m1","kind":"fact","title":"Blue door","quote":"the house had a blue door","segment_span":{"start_word":0,"end_word":5},
      "people_refs":[],"place_text":null,"anchors":[],"same_as_memory_ids":[],"continues_candidate_id":null,"story_ref":null,"story_title_hint":null,
      "collection_hint":null,"chapter_hint":null,"confidence":0.9,"entity_refs":[{"text":"the house","kind":"thing","likely_entity_id":null}],
      "about_ref":"t1","domain_hint":"home"}],
     "mentions":[{"text":"the house","kind":"thing","likely_alias_of_person_id":null,"confidence":0.8,"relation_text":null,"ref":"t1","likely_entity_id":null,"title":null,"domain_hint":"home"}],
     "flags":{"disclosure":"none","wants_to_stop":false,"wants_to_change_subject":false}}
    """
    let out = try ExtractorOutput.decode(from: Data(json.utf8))
    #expect(out.memories[0].entityRefs == [EntityRefOut(text: "the house", kind: .thing, likelyEntityID: nil)])
    #expect(out.memories[0].aboutRef == "t1" && out.memories[0].domainHint == "home")
    #expect(out.mentions[0].kind == .thing && out.mentions[0].ref == "t1")
    let again = try ExtractorOutput.decode(from: try out.encoded())
    #expect(again == out, "round-trips")
}

@Test func v5PayloadStillDecodes() throws {
    let json = #"{"ref":"m","kind":"event","title":"T","quote":"q","segment_span":{"start_word":0,"end_word":0},"people_refs":[],"place_text":"Lisbon","anchors":[],"same_as_memory_ids":[],"collection_hint":null,"chapter_hint":null,"confidence":0.5}"#
    let out = try CandidatePayload.decode(MemoryOut.self, from: json)
    #expect(out.entityRefs.isEmpty && out.aboutRef == nil)
    #expect(out.allEntityRefs == [EntityRefOut(text: "Lisbon", kind: .place, likelyEntityID: nil)], "place_text reads as a place ref")
}

@Test func schemaListsThingAndIdea() throws {
    let mention = try #require((ExtractorSchema.json["properties"] as? [String: Any])?["mentions"] as? [String: Any])
    let props = try #require((mention["items"] as? [String: Any])?["properties"] as? [String: Any])
    #expect((props["kind"] as? [String: Any])?["enum"] as? [String] == ["person", "place", "thing", "idea"])
    #expect(props["ref"] != nil && props["title"] != nil && props["likely_entity_id"] != nil)
}

@Test func promptV6LoadsWithTheIdeaTitleRule() throws {
    #expect(ExtractorConfig.default.version == "v6")
    let text = try ExtractorPrompt.system(version: "v6")
    #expect(text.contains("A thing, place or idea named in the segment is a mention, not a memory. A sentence that describes it is a fact about it."))
    #expect(text.contains("Never write a title in your own words."))
}

@Test func ideaTitleNotInTheSegmentFallsBack() {
    let segment = "I always believed hard work was everything"
    let output = ExtractorOutput(memories: [], mentions: [
        MentionOut(text: "hard work was everything", kind: .idea, likelyAliasOfPersonID: nil, confidence: 0.7, ref: "i1", title: "Work ethic matters"),
    ], flags: .none)
    let validated = OutputValidator.validate(output, segmentText: segment, words: segment.split(separator: " ").map(String.init))
    guard case .mention(let kept)? = validated.accepted.first else { Issue.record("the idea card is kept, not dropped"); return }
    #expect(kept.title == nil, "a composed title is removed")
    #expect(IdeaTitle.title(proposed: kept.title, segmentText: segment, toldOn: oct25, calendar: utc) == "An idea you mentioned on 25 October")
    #expect(IdeaTitle.verbatim("Hard work was everything.", in: segment) == "Hard work was everything.", "the person's words, any case")
}

@Test func ideaTitleOverEightWordsFallsBack() {
    let segment = "I always believed that if you work hard enough every single day it pays"
    #expect(IdeaTitle.verbatim("if you work hard enough every single day it", in: segment) == nil, "nine words")
    #expect(IdeaTitle.verbatim("work hard enough every single day", in: segment) != nil)
}

// MARK: - Keep

private struct Env {
    let store: ExtractionStore, actions: CandidateActions, segment: Segment
    init(_ text: String = "the house had a blue door and I always believed hard work was everything") throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
        let (session, _) = try StoreFixtures.session(in: store.sessions, segments: [text])
        segment = try store.sessions.segments(in: session)[0]
    }

    func memory(_ kind: MemoryKind, title: String = "Blue door", refs: [EntityRefOut] = [], about: String? = nil, ordinal: Int = 0) throws -> Candidate {
        let out = MemoryOut(ref: "m\(ordinal)", kind: kind, title: title, quote: "the house had a blue door", segmentSpan: WordSpan(startWord: 0, endWord: 5),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9,
                            entityRefs: refs, aboutRef: about)
        let c = StoreFixtures.candidate(segment.id, ordinal: ordinal, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return c
    }

    func mention(_ text: String, _ kind: MentionKind, ref: String, title: String? = nil, ordinal: Int, status: CandidateStatus = .pending) throws -> Candidate {
        let out = MentionOut(text: text, kind: kind, likelyAliasOfPersonID: nil, confidence: 0.8, ref: ref, title: title)
        var c = StoreFixtures.candidate(segment.id, ordinal: ordinal, kind: .entity, payload: try CandidatePayload.encode(out))
        c.status = status
        try store.candidates.insert(c)
        return c
    }
}

@Test func aboutRefLandsADetail() throws {
    let env = try Env()
    _ = try env.mention("the house", .thing, ref: "t1", ordinal: 1, status: .accepted)
    let kept = try env.actions.acceptMemory(try env.memory(.fact, about: "t1"))
    let house = try #require(try env.store.entities.find(type: .thing, title: "the house"))
    #expect(try env.store.entities.details(of: house.id).map(\.id) == [kept.memory.id])
    #expect(try env.store.entities.moments(of: house.id).isEmpty)
}

@Test func selfLandsOnTheOwner() throws {
    let env = try Env()
    try env.store.profile.save(Profile(displayName: "Sam", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let kept = try env.actions.acceptMemory(try env.memory(.feeling, about: "self"))
    let owner = try #require(try env.store.profile.owner())
    #expect(try env.store.entities.details(of: owner.entityID).map(\.id) == [kept.memory.id], "About you lists it")
}

@Test func noAboutRefLandsInAbout() throws {
    let env = try Env()
    let kept = try env.actions.acceptMemory(try env.memory(.goal))
    #expect(try env.store.entities.links(of: kept.memory.id).isEmpty)
    #expect(try env.store.memories.aboutMemories(includingHidden: false).map(\.id) == [kept.memory.id])
}

@Test func eventNeverBecomesADetail() throws {
    let env = try Env()
    _ = try env.mention("the house", .thing, ref: "t1", ordinal: 1, status: .accepted)
    let kept = try env.actions.acceptMemory(try env.memory(.event, refs: [EntityRefOut(text: "the house", kind: .thing, likelyEntityID: nil)], about: "t1"))
    let links = try env.store.entities.links(of: kept.memory.id)
    #expect(links.map(\.link.relation) == [.mention], "a moment names the house; it is not a fact about it")
}

@Test func entityMentionLinksEverySegmentMemory() throws {
    let env = try Env("we painted the house and then the house was sold")
    let a = try env.actions.acceptMemory(try env.memory(.event, title: "Painting", refs: [EntityRefOut(text: "the house", kind: .thing, likelyEntityID: nil)], ordinal: 0))
    let card = try env.mention("the house", .thing, ref: "t1", ordinal: 2)
    let house = try env.actions.acceptEntity(card)
    #expect(house.type == .thing)
    #expect(try env.store.entities.moments(of: house.id).map(\.id) == [a.memory.id], "Keep linked it and the card reused the same entity")
    #expect(try env.store.entities.spans(of: house.id).count == 1, "its first telling plays")
    #expect(try env.store.candidates.fetch(card.id)?.status == .accepted)
}

@Test func wrongTypeIsOneTap() throws {
    let env = try Env()
    let card = try env.mention("the house", .thing, ref: "t1", ordinal: 1)
    let place = try env.actions.acceptEntity(card, as: .place)
    #expect(place.type == .place && place.title == "the house")
    #expect(try env.store.entities.find(type: .thing, title: "the house") == nil)

    let other = try env.mention("blue door", .thing, ref: "t2", ordinal: 2)
    try env.actions.notAnEntity(other)
    #expect(try env.store.candidates.fetch(other.id)?.status == .dismissed)
    #expect(try env.store.entities.find(type: .thing, title: "blue door") == nil, "Not any of these creates nothing")
}

@Test func ideaWithoutVerbatimTitleGetsTheDefault() throws {
    let env = try Env()
    let card = try env.mention("hard work was everything", .idea, ref: "i1", title: nil, ordinal: 1)
    let idea = try env.actions.acceptEntity(card)
    #expect(idea.title.hasPrefix("An idea you mentioned on "))
    let named = try env.mention("hard work", .idea, ref: "i2", title: "hard work was everything", ordinal: 2)
    #expect(try env.actions.acceptEntity(named).title == "hard work was everything")
}

@Test func carriedMentionIsARecordNotACard() {
    let memory = MemoryOut(ref: "m1", kind: .fact, title: "Blue door", quote: "q", segmentSpan: WordSpan(startWord: 0, endWord: 0), peopleRefs: [], placeText: nil,
                           anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, aboutRef: "t1")
    let house = MentionOut(text: "the house", kind: .thing, likelyAliasOfPersonID: nil, confidence: 0.8, ref: "t1")
    let car = MentionOut(text: "the car", kind: .thing, likelyAliasOfPersonID: nil, confidence: 0.8, ref: "t2")
    #expect(ExtractionQueue.carried(house, by: [.memory(memory)]))
    #expect(!ExtractionQueue.carried(car, by: [.memory(memory)]), "a thing no memory carries gets its own card")
}

@Test func packetCarriesEntitiesWithinBudget() {
    let segment = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "", status: .pending)
    let house = Entity(type: .thing, title: "the house")
    var hidden = Entity(type: .thing, title: "the diary")
    hidden.excludedFromAI = true
    let many = (0..<400).map { (Entity(type: .idea, title: "idea number \($0) with a fairly long title to fill the budget"), Optional("a detail line that takes some room")) }
    let packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open",
                                            entities: [(house, "it had a blue door"), (hidden, "secret")] + many)
    #expect(packet.entities.first == ContextPacket.EntityEntry(id: house.id.rawValue, type: "thing", title: "the house", detail: "it had a blue door"))
    #expect(!packet.entities.contains { $0.title == "the diary" }, "an entity excluded from AI is never sent")
    #expect(packet.entities.count < 402, "the budget trims entities")
    #expect(ContextPacketBuilder.estimate(String(decoding: (try? packet.encodedJSON()) ?? Data(), as: UTF8.self)) <= ContextPacketBuilder.defaultBudgetTokens)
}

// Review of PR #11, round 3.
@Test func keepingAnEntityNeverTagsItFromTheModelsHint() throws {
    let env = try Env()
    let out = MentionOut(text: "the house", kind: .thing, likelyAliasOfPersonID: nil, confidence: 0.8, ref: "t1", domainHint: "home")
    let card = StoreFixtures.candidate(env.segment.id, ordinal: 1, kind: .entity, payload: try CandidatePayload.encode(out))
    try env.store.candidates.insert(card)
    let house = try env.actions.acceptEntity(card)
    #expect(try env.store.tags.tags(of: .entity, house.id.rawValue).isEmpty, "a tag takes a tap on the hint card, not a Keep")
}

@Test func twoIdeasWithTheDatedDefaultTitleStayTwo() throws {
    let env = try Env()
    let first = try env.actions.acceptEntity(try env.mention("hard work was everything", .idea, ref: "i1", title: nil, ordinal: 1))
    let second = try env.actions.acceptEntity(try env.mention("a house should have one quiet room", .idea, ref: "i2", title: nil, ordinal: 2))
    #expect(first.title == second.title && first.id != second.id, "the same default title never merges two ideas")
    #expect(try env.store.entities.entities(type: .idea).count == 2)
}
