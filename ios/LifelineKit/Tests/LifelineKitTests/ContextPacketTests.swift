import Foundation
import Testing
@testable import LifelineKit

private func seg(_ i: Int, _ text: String) -> Segment {
    Segment(id: .init(), sessionID: SessionID(rawValue: "s"), index: i, startMs: i * 10_000, endMs: i * 10_000 + 5_000, text: text, status: .pending)
}
private func person(_ name: String, owner: Bool = false, aliases: [String] = []) -> (Person, [Alias]) {
    let p = Person(id: .init(), displayName: name, notes: nil, isOwner: owner, birthDate: nil, birthDateOrigin: nil)
    return (p, aliases.map { Alias(personID: p.id, text: $0) })
}

@Test func keepsOnlyTheLastTwoPreviousSegments() {
    let previous = [seg(0, "zero"), seg(1, "one"), seg(2, "two")]
    let packet = ContextPacketBuilder.build(segment: seg(3, "three"), previous: previous, people: [], memories: [], profileFreeText: nil, stage: "open")
    #expect(packet.previousSegments == ["one", "two"])
}

@Test func capsPeopleAtFiftyAndExcludesTheOwner() {
    var people = [person("Jake", owner: true)]
    people += (0..<60).map { person("Person \($0)", aliases: ["p\($0)"]) }
    let packet = ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: people, memories: [], profileFreeText: nil, stage: "open")
    #expect(packet.people.count == 50)
    #expect(!packet.people.contains { $0.name == "Jake" })
    #expect(packet.people[0].aliases == ["p0"])
}

@Test func memoriesOfThisSessionCarryTheirTitles() {
    let memory = StoreFixtures.memory(from: CandidateID(), title: "The blue door")
    let packet = ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: [], memories: [memory], profileFreeText: "I grew up in Fresno", stage: "middle")
    #expect(packet.memories.map(\.title) == ["The blue door"])
    #expect(packet.memories[0].id == memory.id.rawValue && packet.memories[0].rangeText == nil)
    #expect(packet.stage == "middle" && packet.profileFreeText == "I grew up in Fresno")
    #expect(packet.chapters.isEmpty && packet.curiosity.isEmpty)
}

@Test func userMessageNumbersEveryWord() throws {
    let words = ["the", "garden", "behind", "the", "house"]
    let packet = ContextPacketBuilder.build(segment: seg(0, "the garden behind the house"), previous: [], people: [], memories: [], profileFreeText: nil, stage: "open")
    let message = try ExtractorPrompt.userMessage(segmentText: "the garden behind the house", words: words, packet: packet)
    #expect(message.contains("0:the") && message.contains("4:house"))
    #expect(message.contains("the garden behind the house"))
    #expect(message.contains("\"stage\""))
}

@Test func packetIsStableJSON() throws {
    let (p, a) = person("Maya", aliases: ["my sister", "Mai"])
    let build = { ContextPacketBuilder.build(segment: seg(0, "x"), previous: [seg(1, "y")], people: [(p, a)], memories: [], profileFreeText: nil, stage: "open") }
    #expect(try build().encodedJSON() == build().encodedJSON())
    let text = String(decoding: try build().encodedJSON(), as: UTF8.self)
    #expect(text.firstRange(of: "\"chapters\"")!.lowerBound < text.firstRange(of: "\"people\"")!.lowerBound)
}

@Test func packetCarriesChaptersAndOpenQuestions() {
    let chapter = Chapter(id: .init(), title: "The Boston years", range: .year(2011, origin: .derived, evidence: nil), order: 0)
    let untitled = Chapter(id: .init(), title: nil, range: .unplaced, order: 1)
    let questions = (0..<12).map { CuriosityItem(id: .init(), kind: .unresolvedAnchor, text: "q\($0)", payoffCount: 12 - $0, status: .open, sourceMemoryID: nil, targetMemoryID: nil) }
    let packet = ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: [], memories: [], profileFreeText: nil, stage: "open",
                                            chapters: [chapter, untitled], curiosity: questions)
    #expect(packet.chapters.map(\.title) == ["The Boston years", "untitled"])
    #expect(packet.chapters[0].rangeText == "2011" && packet.chapters[1].rangeText == nil)
    #expect(packet.curiosity.count == 10 && packet.curiosity.first == "q0")
}

@Test func excludedMemoriesNeverEnterThePacket() {
    var kept = StoreFixtures.memory(from: CandidateID(), title: "The blue door")
    var excluded = StoreFixtures.memory(from: CandidateID(), title: "Something private")
    excluded.excludedFromAI = true
    kept.hiddenFromTimeline = true   // hidden from browsing is not excluded from AI
    let packet = ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: [], memories: [kept, excluded], profileFreeText: nil, stage: "open")
    #expect(packet.memories.map(\.title) == ["The blue door"])
}

@Test func relatedMemoriesLeadThePacketAndAreMarked() {
    let a = StoreFixtures.memory(from: CandidateID(), title: "Orange house")
    let b = StoreFixtures.memory(from: CandidateID(), title: "The canal")
    var secret = StoreFixtures.memory(from: CandidateID(), title: "Private")
    secret.excludedFromAI = true
    let packet = ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: [], memories: [b, a], profileFreeText: nil, stage: "open",
                                            related: [a, secret])
    #expect(packet.memories.map(\.title) == ["Orange house", "The canal"], "related first, no duplicate, excluded never")
    #expect(packet.memories[0].related == true && packet.memories[1].related == nil)
}

@Test func packetJSONOmitsRelatedWhenNil() throws {
    let a = StoreFixtures.memory(from: CandidateID(), title: "Orange house")
    let plain = ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: [], memories: [a], profileFreeText: nil, stage: "open")
    #expect(!String(decoding: try plain.encodedJSON(), as: UTF8.self).contains("related"))
    let marked = ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: [], memories: [], profileFreeText: nil, stage: "open", related: [a])
    #expect(String(decoding: try marked.encodedJSON(), as: UTF8.self).contains("\"related\" : true"))
}

// MARK: - M5: pending cards, stories, the budget

private func pendingCandidate(_ segment: SegmentID, title: String, quote: String, storyRef: String?) throws -> Candidate {
    let out = MemoryOut(ref: "m", kind: .event, title: title, quote: quote, segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [], placeText: nil,
                        anchors: [], storyRef: storyRef, collectionHint: nil, chapterHint: nil, confidence: 0.9)
    return StoreFixtures.candidate(segment, payload: try CandidatePayload.encode(out))
}

@Test func pendingCandidatesAndStoriesRideInThePacket() throws {
    let card = try pendingCandidate(SegmentID(), title: "Maya climbed it", quote: "my sister Maya climbed it", storyRef: "s-ref")
    let story = Story(id: .init(), title: "The door summer", chapterID: nil, createdAt: .now)
    let a = StoreFixtures.memory(from: CandidateID(), title: "The blue door")
    let b = StoreFixtures.memory(from: CandidateID(), title: "The red gate")
    let packet = ContextPacketBuilder.build(segment: seg(2, "x"), previous: [], people: [], memories: [a], profileFreeText: nil, stage: "open",
                                            pending: [card], stories: [(story, [a, b])])
    #expect(packet.pending == [ContextPacket.PendingEntry(candidateID: card.id.rawValue, title: "Maya climbed it", quote: "my sister Maya climbed it", storyRef: "s-ref")])
    #expect(packet.stories == [ContextPacket.StoryEntry(id: story.id.rawValue, title: "The door summer", momentTitles: ["The blue door", "The red gate"])])
}

@Test func budgetTruncatesWholeEntriesFromTheLeastRelevantSectionFirst() throws {
    let people = (0..<40).map { person("Person number \($0)", aliases: ["alias \($0)"]) }
    let questions = (0..<40).map { CuriosityItem(id: .init(), kind: .unresolvedAnchor, text: "when did the long thing number \($0) happen", payoffCount: 1, status: .open, sourceMemoryID: nil, targetMemoryID: nil) }
    let limits = ContextPacketLimits(previousSegments: 2, people: 50, curiosity: 50)
    let build = { ContextPacketBuilder.build(segment: seg(0, "x"), previous: [], people: people, memories: [], profileFreeText: nil, stage: "open",
                                             limits: limits, curiosity: questions, budgetTokens: 800) }
    let packet = build()
    #expect(packet.curiosity.count == 1, "curiosity is the least relevant: it keeps only its first entry")
    #expect(packet.people.count > 1 && packet.people.count < 40, "people are trimmed to the ceiling, whole entries at a time")
    #expect(ContextPacketBuilder.estimate(String(decoding: try packet.encodedJSON(), as: UTF8.self)) <= 800 + 60)
    #expect(try build().encodedJSON() == packet.encodedJSON())
}

@Test func budgetKeepsFirstEntriesAndProfile() throws {
    let memories = (0..<3).map { StoreFixtures.memory(from: CandidateID(), title: "Memory \($0)") }
    let people = (0..<3).map { person("Person \($0)") }
    let profile = String(repeating: "I grew up in a small town by a canal. ", count: 50)
    let packet = ContextPacketBuilder.build(segment: seg(1, "x"), previous: [seg(0, "earlier")], people: people, memories: memories, profileFreeText: profile, stage: "open",
                                            chapters: [Chapter(id: .init(), title: "Boston", range: .unplaced, order: 0)], budgetTokens: 50)
    #expect(packet.memories.count == 1 && packet.people.count == 1 && packet.chapters.count == 1 && packet.previousSegments.count == 1)
    #expect(packet.profileFreeText == profile, "profile free text is never dropped")
}

@Test func estimateIsCharactersOverFour() {
    #expect(ContextPacketBuilder.estimate("") == 1 && ContextPacketBuilder.estimate(String(repeating: "a", count: 400)) == 100)
}
