import Foundation

/// What stands for a memory where one line is needed. A moment has a title that names it. A
/// fact, a feeling or a goal has no event to name, so the person's own words stand for it.
public enum MemoryLabel {
    public static let storedTitleWords = 8

    /// The start of the cleaned quote, at most eight words, cut at a word. The store needs a
    /// title for every memory; this is the one a fact, feeling or goal gets. Empty only when
    /// the quote has no word.
    public static func storedTitle(quote: String) -> String {
        ReadableQuote.text(quote, maxWords: storedTitleWords)
    }

    /// The heading a screen shows: the title for a moment, the cleaned quote in quotation marks
    /// for the rest.
    public static func heading(for memory: Memory) -> String {
        if memory.isMoment { return memory.title }
        let quote = ReadableQuote.text(memory.summaryQuote)
        return quote.isEmpty ? memory.title : "\u{201C}\(quote)\u{201D}"
    }
}
