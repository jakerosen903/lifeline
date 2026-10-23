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
