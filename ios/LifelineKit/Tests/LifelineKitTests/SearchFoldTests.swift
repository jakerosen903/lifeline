import Testing
@testable import LifelineKit

struct SearchFoldTests {
    @Test func caseAndDiacriticsFold() {
        #expect(SearchFold.fold("Zoë") == "zoe")
        #expect(SearchFold.fold("SÃO Paulo") == "sao paulo")
        #expect(SearchFold.fold("ＭＡＹＡ") == "maya", "full-width letters")
    }
    @Test func anApostropheJoinsAndOtherMarksSplit() {
        #expect(SearchFold.fold("Dad's Volvo") == "dads volvo")
        #expect(SearchFold.fold("Dad\u{2019}s Volvo") == "dads volvo", "a curly apostrophe")
        #expect(SearchFold.fold("St. Louis") == "st louis")
        #expect(SearchFold.fold("tree-house, 1999!") == "tree house 1999")
        #expect(SearchFold.fold("  the\n lake \t") == "the lake")
    }
    @Test func aTextWithNoLetterOrDigitFoldsToNothing() {
        for text in ["", "   ", "…", "!!", "'", "— —"] { #expect(SearchFold.queryWords(text).isEmpty) }
    }
    @Test func aLongQueryIsCutBeforeFolding() {
        let long = String(repeating: "lake ", count: 2_000)          // 10 000 characters
        #expect(SearchFold.queryWords(long).count == 40, "200 characters hold 40 words")
        #expect(SearchFold.queryWords(String(repeating: "x", count: 10_000)) == [String(repeating: "x", count: 200)])
    }
    @Test func wordsKeepTheirOrder() {
        #expect(SearchFold.words("Maya's graduation, in Ohio.") == ["mayas", "graduation", "in", "ohio"])
    }
    @Test func anEmojiIsNotAWord() {
        #expect(SearchFold.words("the lake 🌊") == ["the", "lake"])
    }
}
