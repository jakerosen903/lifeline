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
