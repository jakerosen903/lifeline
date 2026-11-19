import Foundation
import Testing
@testable import LifelineKit

struct SearchSnippetTests {
    // MARK: - Fixtures (invented)

    private static func memory(_ title: String, kind: MemoryKind, quote: String) -> Memory {
        Memory(id: MemoryID(rawValue: "m-\(title)"), title: title, summaryQuote: quote, visibility: .timeline, chapterID: nil,
               createdFromCandidateID: CandidateID(rawValue: "c-\(title)"), createdAt: Date(timeIntervalSince1970: 1_000_000_000), kind: kind)
    }

    private let titleHit = SearchResults.MemoryHit(memory: memory("The long drive", kind: .event, quote: "we drove all night"), match: .titleWords)
    private let factHit = SearchResults.MemoryHit(
        memory: memory("Took things apart", kind: .fact, quote: "I was always the kid who dismantled radios"),
        match: .text, matchedText: "I was always the kid who dismantled radios")
    private let factBeyond = SearchResults.MemoryHit(
        memory: memory("Never sat still", kind: .fact, quote: "I never could sit still"),
        match: .text, matchedText: "I never could sit still in Mrs Okafor's classroom")
    private let momentByQuote = SearchResults.MemoryHit(
        memory: memory("The long drive", kind: .event, quote: "we drove all night"),
        match: .text, matchedText: "we drove all night")

    // MARK: - around

    @Test func theSnippetCentresOnTheFirstMatch() throws {
        let said = "we drove all night through Ohio and he kept an old harmonica in the glove box the whole way to the coast"
        let snippet = try #require(SearchSnippet.around(said, query: "harmonica"))
        #expect(snippet.text == "\u{201C}…Ohio and he kept an old harmonica in the glove box the whole way…\u{201D}")
        #expect(snippet.parts.filter(\.isMatch).map(\.text) == ["harmonica"])
    }
    @Test func aShortTextIsShownWhole() {
        #expect(SearchSnippet.around("an old harmonica", query: "harm")?.text == "\u{201C}an old harmonica\u{201D}")
    }
    @Test func everyMatchedWordInTheWindowIsMarked() {
        #expect(SearchSnippet.around("the glove box held a harmonica", query: "harmonica glove")?.parts.filter(\.isMatch).map(\.text) == ["glove", "harmonica"])
    }
    @Test func theWordsAreAsSaidNotCleaned() {
        #expect(SearchSnippet.around("um, it was, like, Dad's harmonica, you know", query: "dads")?.text == "\u{201C}um, it was, like, Dad's harmonica, you know\u{201D}")
        #expect(SearchSnippet.around("um, it was Dad's harmonica", query: "dads")?.parts.first(where: \.isMatch)?.text == "Dad's", "the mark covers the word as stored")
    }
    @Test func noMatchNoSnippet() {
        #expect(SearchSnippet.around("the lake", query: "harmonica") == nil)
        #expect(SearchSnippet.around("", query: "lake") == nil)
        #expect(SearchSnippet.around("the lake", query: "…") == nil)
    }
    @Test func aMatchNearTheStartCutsOnlyTheEnd() {
        let said = "harmonica one two three four five six seven eight nine"
        #expect(SearchSnippet.around(said, query: "harmonica")?.text == "\u{201C}harmonica one two three four five six seven…\u{201D}")
    }
    @Test func aMatchNearTheEndCutsOnlyTheStart() {
        let said = "one two three four five six seven eight harmonica"
        #expect(SearchSnippet.around(said, query: "harmonica")?.text == "\u{201C}…three four five six seven eight harmonica\u{201D}")
    }
    @Test func lineBreaksAndRepeatedSpacesAreKeptAsSaid() {
        #expect(SearchSnippet.around("an old\n harmonica", query: "harmonica")?.text == "\u{201C}an old\n harmonica\u{201D}")
    }
    @Test func aJoinedWordIsMarkedWhole() {
        #expect(SearchSnippet.around("we met her in-law at the lake", query: "law")?.parts.filter(\.isMatch).map(\.text) == ["in-law"])
    }
    @Test func theQueryIsCutAtItsLimit() {
        let query = "harmonica " + String(repeating: "x", count: SearchFold.maxQueryLength)
        #expect(SearchSnippet.around("a harmonica", query: query)?.parts.filter(\.isMatch).map(\.text) == ["harmonica"])
    }

    // MARK: - line

    @Test func aTitleMatchHasNoSecondLine() {
        #expect(SearchSnippet.line(for: titleHit, query: "drive") == nil)
    }
    @Test func aFactFoundInItsQuoteHasNoSecondLine() {
        #expect(SearchSnippet.line(for: factHit, query: "radios") == nil, "the heading already shows the words")
    }
    @Test func aFactFoundBeyondItsQuoteShowsTheWords() {
        #expect(SearchSnippet.line(for: factBeyond, query: "classroom")?.parts.contains { $0.isMatch && $0.text == "classroom" } == true)
    }
    @Test func aMomentFoundInItsQuoteShowsTheWords() {
        #expect(SearchSnippet.line(for: momentByQuote, query: "night")?.text == "\u{201C}we drove all night\u{201D}")
    }
    @Test func theLineCentresOnAWordTheTitleDoesNotShow() throws {
        // "long" is in the heading; "harmonica" is why the memory was found, and is outside a window centred on "long".
        let hit = SearchResults.MemoryHit(
            memory: Self.memory("The long drive", kind: .event, quote: "we drove all night"), match: .text,
            matchedText: "long ago one two three four five six seven eight nine harmonica in the car")
        let line = try #require(SearchSnippet.line(for: hit, query: "long harmonica"))
        #expect(line.parts.filter(\.isMatch).map(\.text) == ["harmonica"])
        #expect(line.text == "\u{201C}…four five six seven eight nine harmonica in the car\u{201D}")
    }
    @Test func aFactWhoseQuoteHoldsOnlySomeQueryWordsShowsTheWords() {
        #expect(SearchSnippet.line(for: factBeyond, query: "sit classroom") != nil)
    }
}
