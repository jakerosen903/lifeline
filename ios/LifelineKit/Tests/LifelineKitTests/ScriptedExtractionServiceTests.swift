import Foundation
import Testing
@testable import LifelineKit

@Test func scriptedHeavyModeFlagsTheSecondSegmentAsPastHarm() async throws {
    let quiet = ScriptedExtractionService(delayMs: 0)
    let heavy = ScriptedExtractionService(delayMs: 0, heavy: true)
    let packet = ContextPacketBuilder.build(segment: Segment(id: .init(), sessionID: .init(), index: 1, startMs: 0, endMs: 1, text: "", status: .pending),
                                            previous: [], people: [], memories: [], profileFreeText: nil, stage: "open")
    let maya = ExtractionRequest(segmentID: .init(), segmentText: "my sister Maya climbed it in 1998 every summer",
                                 words: "my sister Maya climbed it in 1998 every summer".split(separator: " ").map(String.init), packet: packet)
    #expect(try await quiet.extract(maya).output.flags.disclosure == .none)
    let flagged = try await heavy.extract(maya).output
    #expect(flagged.flags.disclosure == .past && flagged.flags.isHeavy)
    let door = ExtractionRequest(segmentID: .init(), segmentText: "the house had a blue door when I was six before Maya climbed it",
                                 words: ["the", "house"], packet: packet)
    #expect(try await heavy.extract(door).output.flags.disclosure == .none, "only the Maya segment is heavy, so a card has already shown")
}

@Test func scriptedRetellingNamesTheEarlierBlueDoor() async throws {
    let service = ScriptedExtractionService(delayMs: 0)
    let earlier = StoreFixtures.memory(from: CandidateID(), title: "The blue door")
    let segment = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "", status: .pending)
    let withPacket = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open", related: [earlier])
    let without = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open")
    let text = "the house had a blue door when I was six before Maya climbed it"
    let words = text.split(separator: " ").map(String.init)
    let retold = try await service.extract(ExtractionRequest(segmentID: .init(), segmentText: text, words: words, packet: withPacket)).output
    #expect(retold.memories.first?.sameAsMemoryID == earlier.id.rawValue)
    let first = try await service.extract(ExtractionRequest(segmentID: .init(), segmentText: text, words: words, packet: without)).output
    #expect(first.memories.first?.sameAsMemoryID == nil)
}

@Test func scriptedThirdSegmentContinuesMaya() async throws {
    let service = ScriptedExtractionService(delayMs: 0)
    let segment = Segment(id: .init(), sessionID: .init(), index: 2, startMs: 0, endMs: 1, text: "", status: .pending)
    var packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open")
    let text = "we moved away the year before she was born"
    let words = text.split(separator: " ").map(String.init)
    let alone = try await service.extract(ExtractionRequest(segmentID: .init(), segmentText: text, words: words, packet: packet)).output
    #expect(alone.memories.isEmpty)
    let maya = CandidateID()
    packet.pending = [ContextPacket.PendingEntry(candidateID: maya.rawValue, title: "Maya climbed it", quote: "my sister Maya climbed it in 1998", storyRef: nil)]
    let continued = try await service.extract(ExtractionRequest(segmentID: .init(), segmentText: text, words: words, packet: packet)).output
    #expect(continued.memories.count == 1 && continued.memories.first?.continuesCandidateID == maya.rawValue)
    #expect(continued.memories.first?.segmentSpan == WordSpan(startWord: 0, endWord: words.count - 1))
}

@Test func scriptedBlueDoorAndMayaShareAStory() async throws {
    let service = ScriptedExtractionService(delayMs: 0)
    let segment = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "", status: .pending)
    let packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open")
    func run(_ text: String) async throws -> MemoryOut? {
        try await service.extract(ExtractionRequest(segmentID: .init(), segmentText: text, words: text.split(separator: " ").map(String.init), packet: packet)).output.memories.first
    }
    let door = try await run("the house had a blue door when I was six before Maya climbed it")
    let maya = try await run("my sister Maya climbed it in 1998 every summer")
    #expect(door?.storyRef == "story-scripted" && maya?.storyRef == "story-scripted")
    #expect(maya?.storyTitleHint == "The blue door summer" && door?.storyTitleHint == nil)
}

@Test func scriptedRetellingNamesEveryEarlierBlueDoor() async throws {
    let service = ScriptedExtractionService(delayMs: 0)
    let one = StoreFixtures.memory(from: CandidateID(), title: "The blue door")
    let two = StoreFixtures.memory(from: CandidateID(), title: "The blue door")
    let segment = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "", status: .pending)
    let packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open", related: [one, two])
    let text = "the house had a blue door when I was six before Maya climbed it"
    let out = try await service.extract(ExtractionRequest(segmentID: .init(), segmentText: text, words: text.split(separator: " ").map(String.init), packet: packet)).output
    #expect(out.memories.first?.sameAsMemoryIDs == [one.id.rawValue, two.id.rawValue])
}

@Test func factModeMarksTheBlueDoorAFact() async throws {
    let segment = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "", status: .pending)
    let packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open")
    let text = "the house had a blue door when I was six before Maya climbed it"
    let request = ExtractionRequest(segmentID: .init(), segmentText: text, words: text.split(separator: " ").map(String.init), packet: packet)
    let fact = try await ScriptedExtractionService(delayMs: 0, facts: true).extract(request).output.memories.first
    #expect(fact?.kind == .fact && fact?.title == "The house had a blue door")
    let event = try await ScriptedExtractionService(delayMs: 0).extract(request).output.memories.first
    #expect(event?.kind == .event && event?.title == "The blue door")
}
