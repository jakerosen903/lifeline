import Foundation
import Testing
@testable import LifelineKit

private func detail(_ id: String, _ quote: String, at n: Int) -> Memory {
    Memory(id: MemoryID(rawValue: id), title: id, summaryQuote: quote, visibility: .timeline, chapterID: nil,
           createdFromCandidateID: CandidateID(rawValue: "c-\(id)"), createdAt: Date(timeIntervalSince1970: Double(n)), kind: .fact)
}
private func told(in session: String) -> Telling {
    Telling(sessionID: SessionID(rawValue: session), audioPath: "seed.m4a", range: MsRange(start: 0, end: 4_000), toldAt: .now)
}

@Test func theQuoteIsTheOldestToldDetailCleaned() {
    let quote = ThingQuote.choose(details: [detail("b", "the seats were green", at: 2), detail("a", "um, it smelled like oranges and wet dog", at: 1)],
                                  tellings: [MemoryID(rawValue: "a"): told(in: "calm"), MemoryID(rawValue: "b"): told(in: "calm")], heavySessions: [])
    #expect(quote == "It smelled like oranges and wet dog")
}
@Test func aDetailOfOnlyFillerIsSkipped() {
    #expect(ThingQuote.choose(details: [detail("a", "um, uh", at: 1), detail("b", "the seats were green", at: 2)], tellings: [MemoryID(rawValue: "a"): told(in: "calm"), MemoryID(rawValue: "b"): told(in: "calm")], heavySessions: []) == "The seats were green")
}
@Test func aDetailFromAHeavySessionIsNotChosen() {
    let details = [detail("a", "he clanked all night", at: 1), detail("b", "the seats were green", at: 2)]
    #expect(ThingQuote.choose(details: details, tellings: [MemoryID(rawValue: "a"): told(in: "heavy"), MemoryID(rawValue: "b"): told(in: "calm")], heavySessions: [SessionID(rawValue: "heavy")]) == "The seats were green")
    #expect(ThingQuote.choose(details: details, tellings: [MemoryID(rawValue: "a"): told(in: "calm"), MemoryID(rawValue: "b"): told(in: "calm")], heavySessions: [SessionID(rawValue: "heavy")]) == "He clanked all night")
}
@Test func aDetailWithNoFirstTellingIsNotChosen() {
    // No telling means the session is unknown, so it cannot be known to be calm.
    #expect(ThingQuote.choose(details: [detail("a", "the seats were green", at: 1)], tellings: [:], heavySessions: []) == nil)
}
@Test func noDetailGivesNoQuote() {
    #expect(ThingQuote.choose(details: [], tellings: [:], heavySessions: []) == nil)
    #expect(ThingQuote.choose(details: [detail("a", "um, uh", at: 1)], tellings: [MemoryID(rawValue: "a"): told(in: "calm"), MemoryID(rawValue: "b"): told(in: "calm")], heavySessions: []) == nil)
}
@Test func aLongQuoteIsCutAtTwentyWords() {
    let long = (1...30).map { "w\($0)" }.joined(separator: " ")
    #expect(ThingQuote.choose(details: [detail("a", long, at: 1)], tellings: [MemoryID(rawValue: "a"): told(in: "calm"), MemoryID(rawValue: "b"): told(in: "calm")], heavySessions: [])
            == "W1 " + (2...20).map { "w\($0)" }.joined(separator: " ") + "…")
}
@Test func countLineSaysMomentsAndNothingForNone() {
    #expect(ThingTileText.countLine(0) == nil)
    #expect(ThingTileText.countLine(1) == "1 moment")
    #expect(ThingTileText.countLine(3) == "3 moments")
}
@Test func accessibilityValueJoinsWhatTheTileShows() {
    #expect(ThingTileText.accessibilityValue(moments: 1, placedByGuess: true, quote: "He clanked all night") == "1 moment. Placed by a guess. “He clanked all night”")
    #expect(ThingTileText.accessibilityValue(moments: 0, placedByGuess: false, quote: "I never learned more than three chords") == "“I never learned more than three chords”")
    #expect(ThingTileText.accessibilityValue(moments: 2, placedByGuess: false, quote: nil) == "2 moments")
    #expect(ThingTileText.accessibilityValue(moments: 0, placedByGuess: false, quote: nil) == "")
}
