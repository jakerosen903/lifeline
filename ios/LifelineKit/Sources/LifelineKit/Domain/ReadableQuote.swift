import Foundation

/// A quote cleaned for reading on lists and pages (decision log 2026-10-26; plan decision 19).
/// Display only: the stored text, the memory page and the audio keep every word (PRINCIPLES 1).
///
/// Rules, in this order: fragments, fillers, repeats, the end comma, the capital.
/// - A fragment is a token made only of dashes, dots and commas.
/// - Fillers: "um", "uh" and "erm"; "like" only when a comma stands on both sides (", like,"),
///   because "like" with a comma on one side may be the person's word; "you know" only when a comma follows it or it ends the quote. A removed filler
///   takes its trailing comma with it. A comma before it stays. A "." or "…" it carried moves to
///   the word before, never doubled. A "?" or "!" it carried becomes ".", so a statement never
///   turns into a question or an exclamation.
/// - A word said twice or more in a row keeps one copy: the first as written, without its comma,
///   plus the end marks and closing quotes of the last. "had had" and "that that" stay.
/// - Only a letter is capitalised, and only the first character after opening quotes.
/// - `maxWords` cuts at a word and ends with "…". A value below 1 acts as 1.
public enum ReadableQuote {
    public static func text(_ raw: String, maxWords: Int? = nil) -> String {
        var tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        tokens = tokens.filter { !isFragment($0) }
        tokens = removingFillers(tokens)
        tokens = collapsingRepeats(tokens)
        if let last = tokens.last { tokens[tokens.count - 1] = last.withoutTrailingCommas() }
        if let maxWords, tokens.count > max(maxWords, 1) {
            tokens = Array(tokens.prefix(max(maxWords, 1)))
            let cut = String(tokens.removeLast().reversed().drop { Self.cutMarks.contains($0.unicodeScalars.first!) }.reversed())
            return capitalised((tokens + [cut]).joined(separator: " ")) + "…"
        }
        return capitalised(tokens.joined(separator: " "))
    }

    // MARK: - Rules

    private static let fillerSounds: Set<String> = ["um", "uh", "erm"]
    private static let closers: Set<Character> = ["\"", "\u{201D}", "'", "\u{2019}", "\u{00BB}", ")", "]"]
    private static let repeatable: Set<String> = ["had", "that"]
    private static let fragmentMarks = CharacterSet(charactersIn: "-\u{2013}\u{2014}.\u{2026},")
    private static let cutMarks = CharacterSet(charactersIn: ",;:.-\u{2013}\u{2014}")
    private static let endMarks: Set<Character> = [".", "?", "!", "\u{2026}"]

    private static func isFragment(_ token: String) -> Bool {
        token.unicodeScalars.allSatisfy { fragmentMarks.contains($0) }
    }

    private static func removingFillers(_ tokens: [String]) -> [String] {
        var kept: [String] = []
        var i = 0
        func drop(_ filler: String) {
            // The end mark of a removed filler moves to the word before it.
            guard let mark = filler.last(where: { $0 != "," }), endMarks.contains(mark), let previous = kept.popLast() else { return }
            let bare = previous.withoutTrailingCommas()
            if let end = bare.last, endMarks.contains(end) { kept.append(bare); return }
            kept.append(bare + (mark == "?" || mark == "!" ? "." : String(mark)))
        }
        while i < tokens.count {
            let token = tokens[i], word = core(token)
            if fillerSounds.contains(word) {
                drop(token); i += 1
            } else if word == "like", token.hasSuffix(","), kept.last?.hasSuffix(",") == true {
                drop(token); i += 1
            } else if word == "you", !token.hasSuffix(","), i + 1 < tokens.count, core(tokens[i + 1]) == "know",
                      tokens[i + 1].hasSuffix(",") || i + 2 == tokens.count {
                drop(tokens[i + 1]); i += 2
            } else {
                kept.append(token); i += 1
            }
        }
        return kept
    }

    private static func collapsingRepeats(_ tokens: [String]) -> [String] {
        var kept: [String] = []
        var i = 0
        while i < tokens.count {
            let word = core(tokens[i])
            var j = i + 1
            while !word.isEmpty, j < tokens.count, core(tokens[j]) == word { j += 1 }
            if j - i > 1, !repeatable.contains(word) {
                kept.append(withoutEnding(tokens[i]) + ending(of: tokens[j - 1]))
            } else {
                kept.append(contentsOf: tokens[i..<j])
            }
            i = j
        }
        return kept
    }

    // MARK: - Tokens

    /// The word without the punctuation around it, lowercased, for comparing.
    private static func core(_ token: String) -> String { bareWord(token).lowercased() }

    private static func bareWord(_ token: String) -> String {
        var scalars = Substring(token)
        while let first = scalars.first, !first.isLetter, !first.isNumber { scalars.removeFirst() }
        while let last = scalars.last, !last.isLetter, !last.isNumber { scalars.removeLast() }
        return String(scalars)
    }

    /// The run of end marks and closing quotes a token ends with, after its commas.
    private static func ending(of token: String) -> String {
        String(token.withoutTrailingCommas().reversed().prefix { endMarks.contains($0) || closers.contains($0) }.reversed())
    }

    /// The token as written, without its trailing commas, end marks and closing quotes.
    private static func withoutEnding(_ token: String) -> String {
        let bare = token.withoutTrailingCommas()
        return String(bare.dropLast(ending(of: bare).count))
    }

    private static let openers: Set<Character> = ["\"", "\u{201C}", "'", "\u{2018}", "\u{00AB}", "(", "["]

    /// Only a letter is capitalised: "1999 was" and an emoji start stay as said.
    private static func capitalised(_ text: String) -> String {
        guard let index = text.firstIndex(where: { !$0.isWhitespace && !openers.contains($0) }), text[index].isLetter else { return text }
        return text.replacingCharacters(in: index...index, with: text[index].uppercased())
    }
}

private extension String {
    func withoutTrailingCommas() -> String {
        var s = Substring(self)
        while s.last == "," { s.removeLast() }
        return String(s)
    }
}
