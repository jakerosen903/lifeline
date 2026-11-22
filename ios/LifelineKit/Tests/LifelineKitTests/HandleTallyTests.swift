import Foundation
import Testing
@testable import LifelineKit

// PC-d Task 7: the tally the v6 against v8 comparison prints, on hand-written outputs.

private func memory(handles: [PersonOut] = [], peopleRefs: [String] = []) -> MemoryOut {
    MemoryOut(ref: "m1", kind: .event, title: "At the lake", quote: "we swam", segmentSpan: WordSpan(startWord: 0, endWord: 1),
              peopleRefs: peopleRefs, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9,
              personHandles: handles.map(\.handle), handlePeople: handles)
}

private func output(_ memories: [MemoryOut], people: [PersonOut] = [], mentions: [MentionOut] = []) -> ExtractorOutput {
    ExtractorOutput(people: people, memories: memories, mentions: mentions, flags: .none)
}

private func person(_ handle: String, _ name: String) -> PersonOut {
    PersonOut(handle: handle, saidName: name, relationText: nil, personID: nil)
}

@Test func twoHandlesWithOneNameAcrossSegmentsAreTwoPeople() {
    let tally = HandleTally(outputs: [
        output([memory(handles: [person("p1", "Robyn")], peopleRefs: ["Robyn"])]),
        output([memory(handles: [person("p2", "Robyn")], peopleRefs: ["Robyn"])]),
        output([memory(handles: [person("p1", "Robyn")], peopleRefs: ["Robyn"])]),
    ])
    #expect(tally.people == [.init(handle: "p1", saidNames: ["Robyn"]), .init(handle: "p2", saidNames: ["Robyn"])])
    #expect(tally.holds([["Robyn"], ["Robyn"]]))
    #expect(!tally.holds([["Robyn"]]))
}

@Test func oneHandleUnderTwoNamesIsOnePersonWithBothNames() {
    let tally = HandleTally(outputs: [
        output([memory(handles: [person("p1", "Anselm")])]),
        output([], people: [person("p1", "Sully")]),
    ])
    #expect(tally.people == [.init(handle: "p1", saidNames: ["Anselm", "Sully"])])
    #expect(tally.holds([["Anselm", "Sully"]]))
}

// v6 gives no handles: one person per distinct said name, so two Robyns read as one.
@Test func withNoHandlesEachDistinctSaidNameIsOnePerson() {
    let tally = HandleTally(outputs: [
        output([memory(peopleRefs: ["Robyn"])]),
        output([memory(peopleRefs: ["robyn", "Anselm"])]),
    ])
    #expect(tally.people == [.init(handle: nil, saidNames: ["Robyn"]), .init(handle: nil, saidNames: ["Anselm"])])
    #expect(!tally.holds([["Robyn"], ["Robyn"]]))
}

@Test func aNameWithNoHandleJoinsTheHandleThatSaidIt() {
    let tally = HandleTally(outputs: [output([memory(handles: [person("p1", "Hollis")], peopleRefs: ["Hollis"]), memory(peopleRefs: ["Hollis"])])])
    #expect(tally.people.count == 1)
}

@Test func aPersonMentionWithAHandleCounts() {
    let ottilie = MentionOut(text: "Ottilie", kind: .person, confidence: 0.8, handle: "p1")
    let place = MentionOut(text: "Hale Street", kind: .place, confidence: 0.8)
    let tally = HandleTally(outputs: [output([], mentions: [ottilie, place])])
    #expect(tally.people == [.init(handle: "p1", saidNames: ["Ottilie"])])
}

// A person mention with no handle is not counted: for v6 the count is the said names of `people_refs`.
@Test func aPersonMentionWithNoHandleIsNotCounted() {
    let tally = HandleTally(outputs: [output([], mentions: [MentionOut(text: "Ottilie", kind: .person, confidence: 0.8)])])
    #expect(tally.people.isEmpty)
    #expect(tally.holds([]))
    #expect(!tally.holds([["Ottilie"]]))
}

@Test func blankHandlesAndBlankNamesAreSkipped() {
    let tally = HandleTally(outputs: [output([memory(handles: [person(" ", "Robyn"), person("p2", "  ")], peopleRefs: [""])])])
    #expect(tally.people == [.init(handle: nil, saidNames: ["Robyn"])])
}

// A said name may carry more words than the expected name ("the other Robyn"); the expected name must be a run of its words.
@Test func anExpectedNameMatchesASaidNameThatHoldsItsWords() {
    let tally = HandleTally(outputs: [output([memory(handles: [person("p1", "Robyn"), person("p2", "the other Robyn")])])])
    #expect(tally.holds([["Robyn"], ["Robyn"]]))
    #expect(!tally.holds([["Robyn"], ["Sully"]]))
}

// Each expected person needs its own found person: one person cannot answer for two.
@Test func theExpectedAnswerNeedsOneFoundPersonPerExpectedPerson() {
    let split = HandleTally(outputs: [output([memory(handles: [person("p1", "Anselm"), person("p2", "Sully")])])])
    #expect(!split.holds([["Anselm", "Sully"]]))
    let joined = HandleTally(outputs: [output([memory(handles: [person("p1", "Anselm")])]), output([memory(handles: [person("p1", "Sully")])])])
    #expect(joined.holds([["Anselm", "Sully"]]))
    #expect(!joined.holds([["Anselm"], ["Sully"]]))
}

@Test func theExpectedAnswerIsReadFromTheStoryFixture() throws {
    let url = try #require(Bundle.module.url(forResource: "transcript-v8-two-robyns", withExtension: "json", subdirectory: "Fixtures"))
    #expect(try HandleTally.expectedPeople(inFixture: Data(contentsOf: url)) == [["Robyn"], ["Robyn"]])
    let older = try #require(Bundle.module.url(forResource: "transcript-garden", withExtension: "json", subdirectory: "Fixtures"))
    #expect(try HandleTally.expectedPeople(inFixture: Data(contentsOf: older)) == nil)
}

@Test func everyStoryFixtureImportsAndHasAnExpectedAnswer() throws {
    for story in ["transcript-v8-two-robyns", "transcript-v8-two-names", "transcript-v8-name-alone", "transcript-v8-new-relation"] {
        let url = try #require(Bundle.module.url(forResource: story, withExtension: "json", subdirectory: "Fixtures"))
        let store = ExtractionStore(try AppDatabase.inMemory())
        let session = try TranscriptImport.importTranscript(at: url, into: store.sessions)
        let segments = try store.sessions.segments(in: session)
        #expect((2...3).contains(segments.count), "\(story): \(segments.count) segments")
        #expect(try HandleTally.expectedPeople(inFixture: Data(contentsOf: url)) != nil, "\(story)")
    }
}
