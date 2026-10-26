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

        let words = Self.dashSeparated(text).split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > maxWords { return .dropped("too long") }

        let said = Set(TurnText.tokens(sessionWords.joined(separator: " ")))
        for token in countedTokens(text.split(whereSeparator: \.isWhitespace).map(String.init)) where !said.contains(token) {
            return .dropped("not said: \(token)")
        }
        return .speak(reply.kind == .reflection ? .reflection : .question, text)
    }

    /// A dash joins two words for the count: an em or en dash, or a hyphen between letters.
    private static func dashSeparated(_ text: String) -> String {
        text.replacingOccurrences(of: "[\u{2014}\u{2013}]|(?<=\\p{L})-(?=\\p{L})", with: " ", options: .regularExpression)
    }

    /// Tokens of the words that carry a detail: a capitalized piece that does not open a sentence and is not "I"
    /// or a form of it, and any piece with a digit. Spelled numbers do not count. A word is cut into pieces at
    /// anything but a letter, digit or apostrophe, so "garden,Maya" and "ex-Navy" are checked piece by piece.
    /// Known gap, accepted: a later sentence may open with a name the person never said.
    private static func countedTokens(_ words: [String]) -> [String] {
        var counted: [String] = []
        var opensSentence = true
        for word in words {
            let pieces = word.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}") }).map(String.init)
            for (index, piece) in pieces.enumerated() {
                let tokens = TurnText.tokens(piece)
                if tokens.contains(where: { $0.contains(where: \.isNumber) }) {
                    counted += tokens
                } else if !(index == 0 && opensSentence), !isI(piece), let first = piece.first(where: \.isLetter), first.isUppercase {
                    counted += tokens
                }
            }
            opensSentence = endsSentence(word)
        }
        return counted
    }

    private static let closers = CharacterSet(charactersIn: "\"')]\u{201D}\u{2019}")
    private static let iForms: Set<String> = ["I", "I'm", "I've", "I'd", "I'll"]
    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "st", "mt", "jr", "sr"]

    /// A word ends a sentence with `.`, `?` or `!`, unless the full stop is an abbreviation's or an initial's.
    private static func endsSentence(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: closers)
        guard let last = trimmed.last, ".?!".contains(last) else { return false }
        guard last == "." else { return true }
        let stem = trimmed.dropLast().trimmingCharacters(in: CharacterSet.letters.inverted)
        if abbreviations.contains(stem.lowercased()) { return false }
        return !(stem.count == 1 && stem.first!.isUppercase)
    }

    private static func isI(_ word: String) -> Bool {
        iForms.contains(word.replacingOccurrences(of: "\u{2019}", with: "'"))
    }
}
