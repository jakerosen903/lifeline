import Foundation

/// What the app does with the model's reply, after the client-side checks.
public enum CheckedTurn: Equatable, Sendable {
    case speak(TurnKind, String)
    /// The person asked about the app: speak the fixed copy, never the model's text.
    case aboutApp
    case none
    /// The turn failed a check. It is never repaired. The reason is for the log.
    case dropped(String)
}

/// Drops any reply that is too long or adds a detail the person did not say.
public enum TurnChecks {
    public static func validate(_ reply: InterviewerReply, sessionWords: [String], maxWords: Int = 20) -> CheckedTurn {
        if reply.askedAboutApp { return .aboutApp }
        let text = reply.text ?? ""
        if reply.kind == .none { return text.isEmpty ? .none : .dropped("text with none") }
        guard !text.isEmpty else { return .dropped("empty") }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > maxWords { return .dropped("too long") }

        let said = Set(TurnText.tokens(sessionWords.joined(separator: " ")))
        for token in countedTokens(words) where !said.contains(token) {
            return .dropped("not said: \(token)")
        }
        return .speak(reply.kind == .reflection ? .reflection : .question, text)
    }

    /// Tokens of the words that carry a detail: a capitalized word that does not open a sentence and is not "I"
    /// or a form of it, and any word with a digit. Spelled numbers do not count.
    private static func countedTokens(_ words: [String]) -> [String] {
        var counted: [String] = []
        var opensSentence = true
        for word in words {
            defer { opensSentence = word.trimmingCharacters(in: Self.closers).last.map { ".?!".contains($0) } ?? false }
            let tokens = TurnText.tokens(word)
            if tokens.contains(where: { $0.contains(where: \.isNumber) }) {
                counted += tokens
            } else if !opensSentence, !isI(word), let first = word.first(where: \.isLetter), first.isUppercase {
                counted += tokens
            }
        }
        return counted
    }

    private static let closers = CharacterSet(charactersIn: "\"')]\u{201D}\u{2019}")
    private static let iForms: Set<String> = ["I", "I'm", "I've", "I'd", "I'll"]

    private static func isI(_ word: String) -> Bool {
        let bare = word.replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
        return iForms.contains(bare)
    }
}
