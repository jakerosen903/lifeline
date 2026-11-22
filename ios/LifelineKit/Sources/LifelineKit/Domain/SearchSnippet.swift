import Foundation

/// A line of the person's words around the first match, as said (P1). Display only.
public struct SearchSnippet: Sendable, Equatable {
    public struct Part: Sendable, Equatable {
        public var text: String
        public var isMatch: Bool

        public init(text: String, isMatch: Bool) { self.text = text; self.isMatch = isMatch }
    }

    /// In reading order. Joined, they are the snippet with its quotation marks and any "…".
    public var parts: [Part]

    public var text: String { parts.map(\.text).joined() }

    public static let wordsBefore = 6
    public static let wordsAfter = 7

    private static let openQuote = "\u{201C}", closeQuote = "\u{201D}", cut = "…"

    /// Nil when no word of `text` starts with a query word. The window centres on the first word that starts with
    /// one of `centredOn` (folded query words) when there is one, else on the first match. Every match in it is marked.
    public static func around(_ text: String, query: String, centredOn preferred: [String] = []) -> SearchSnippet? {
        let queryWords = SearchFold.queryWords(query)
        guard !queryWords.isEmpty else { return nil }
        let tokens = tokens(of: text)
        guard let first = tokens.firstIndex(where: { isMatch($0, preferred) }) ?? tokens.firstIndex(where: { isMatch($0, queryWords) })
        else { return nil }

        let start = max(0, first - wordsBefore)
        let end = min(tokens.count - 1, first + wordsAfter)

        var parts: [Part] = []
        func append(_ piece: Substring, isMatch: Bool) {
            guard !piece.isEmpty else { return }
            if !isMatch, let last = parts.last, !last.isMatch {
                parts[parts.count - 1].text += piece
            } else {
                parts.append(Part(text: String(piece), isMatch: isMatch))
            }
        }

        append(Substring(openQuote + (start > 0 ? cut : "")), isMatch: false)
        var cursor = tokens[start].range.lowerBound
        for token in tokens[start...end] where isMatch(token, queryWords) {
            let word = token.markedRange
            append(text[cursor..<word.lowerBound], isMatch: false)
            append(text[word], isMatch: true)
            cursor = word.upperBound
        }
        append(text[cursor..<tokens[end].range.upperBound], isMatch: false)
        append(Substring((end < tokens.count - 1 ? cut : "") + closeQuote), isMatch: false)
        return SearchSnippet(parts: parts)
    }

    /// Nil for a title match, and for a fact, feeling or goal whose quote holds every query word (decision 13).
    /// It centres on a query word the heading does not show, so the line shows why the memory was found.
    public static func line(for hit: SearchResults.MemoryHit, query: String) -> SearchSnippet? {
        guard hit.match == .text, let matchedText = hit.matchedText else { return nil }
        // As in `Search`: the heading is the title for a moment and the cleaned quote for the rest.
        let unshown = Search.unshown(SearchFold.queryWords(query), by: SearchIndex.MemoryEntry.headingWords(of: hit.memory))
        if !hit.memory.isMoment, unshown.isEmpty { return nil }
        return around(matchedText, query: query, centredOn: unshown)
    }

    // MARK: - Private

    private struct Token {
        /// The token as stored, from one white space to the next.
        var range: Range<String.Index>
        /// The token without punctuation at its ends: the part a mark covers.
        var markedRange: Range<String.Index>
        var foldedWords: [String]
    }

    private static func isMatch(_ token: Token, _ queryWords: [String]) -> Bool {
        token.foldedWords.contains { word in queryWords.contains { word.hasPrefix($0) } }
    }

    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace { index = text.index(after: index); continue }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            let range = index..<end
            tokens.append(Token(range: range, markedRange: trimmed(range, in: text), foldedWords: SearchFold.words(String(text[range]))))
            index = end
        }
        return tokens
    }

    /// Drops punctuation at both ends, so "harmonica," marks "harmonica". A token with no letter or digit keeps its range.
    private static func trimmed(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let first = text[range].firstIndex(where: isWord), let last = text[range].lastIndex(where: isWord) else { return range }
        return first..<text.index(after: last)
    }
}
