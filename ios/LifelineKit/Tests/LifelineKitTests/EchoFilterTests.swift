import Testing
@testable import LifelineKit

struct EchoFilterTests {
    private let config = EchoConfig()

    /// One word per 100 ms, starting at `start`.
    private func words(_ text: String, from start: Int) -> [TranscribedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let at = start + index * 100
            return TranscribedWord(text: String(word), range: MsRange(start: at, end: at + 90))
        }
    }

    private func texts(_ words: [TranscribedWord]) -> [String] { words.map(\.text) }

    private let turn = "What was the house like when you were small"
    private var window: PlaybackWindow {
        PlaybackWindow(range: MsRange(start: 1_000, end: 2_000), text: turn)
    }

    @Test func tokensAreLowercaseLettersAndDigitsWithInnerApostrophesDropped() {
        #expect(TurnText.tokens("Maya's 2nd house, WAS big!") == ["mayas", "2nd", "house", "was", "big"])
        #expect(TurnText.tokens("don\u{2019}t") == ["dont"])
        #expect(TurnText.tokens("...") == [])
    }

    @Test func aMatchingRunInsideTheWindowIsRemoved() {
        let heard = words("what was the house like", from: 1_000)
        let person = words("it was yellow", from: 3_000)
        let kept = EchoFilter.personsWords(heard + person, windows: [window], config: config)
        #expect(texts(kept) == ["it", "was", "yellow"])
    }

    @Test func aNonMatchingRunInsideTheWindowStays() {
        let said = words("my grandmother kept chickens", from: 1_000)
        let kept = EchoFilter.personsWords(said, windows: [window], config: config)
        #expect(kept == said)
    }

    @Test func aMatchingRunOutsideTheWindowStays() {
        let said = words("what was the house like", from: 5_000)
        let kept = EchoFilter.personsWords(said, windows: [window], config: config)
        #expect(kept == said)
    }

    @Test func aWordInsideThePadIsStillInTheWindow() {
        let said = words("what was", from: 700)
        #expect(EchoFilter.personsWords(said, windows: [window], config: config).isEmpty)
        let late = words("what was", from: 2_200)
        #expect(EchoFilter.personsWords(late, windows: [window], config: config).isEmpty)
        let tooLate = words("what was", from: 2_301)
        #expect(EchoFilter.personsWords(tooLate, windows: [window], config: config) == tooLate)
    }

    @Test func anInterruptedTurnRemovesOnlyThePlayedPrefix() {
        let heard = words("what was the", from: 1_000)
        let person = words("sorry I need water", from: 1_300)
        let kept = EchoFilter.personsWords(heard + person, windows: [window], config: config)
        #expect(texts(kept) == ["sorry", "I", "need", "water"])
    }

    @Test func oneCoincidentWordStays() {
        let turn = PlaybackWindow(range: MsRange(start: 1_000, end: 2_000), text: "Was that yes or no")
        let said = words("yes", from: 1_200)
        #expect(EchoFilter.personsWords(said, windows: [turn], config: config) == said)
    }

    @Test func aWordWithNoLettersIsKeptAndNeverAligned() {
        let heard = words("what was the", from: 1_000)
        let dash = TranscribedWord(text: "--", range: MsRange(start: 1_150, end: 1_160))
        let kept = EchoFilter.personsWords(heard + [dash], windows: [window], config: config)
        #expect(kept == [dash])
    }

    @Test func windowsAreIndependent() {
        let other = PlaybackWindow(range: MsRange(start: 4_000, end: 5_000), text: "Tell me about your mother")
        let first = words("what was the house", from: 1_000)
        let second = words("tell me about your mother", from: 4_000)
        let kept = EchoFilter.personsWords(first + second, windows: [window, other], config: config)
        #expect(kept.isEmpty)
    }

    @Test func nonMatchingCountsThePersonsWords() {
        #expect(EchoFilter.nonMatchingCount("what was the house", turnText: turn) == 0)
        #expect(EchoFilter.nonMatchingCount("what was the house wait stop", turnText: turn) == 2)
        #expect(EchoFilter.nonMatchingCount("no", turnText: turn) == 1)
        #expect(EchoFilter.nonMatchingCount("", turnText: turn) == 0)
    }
}
