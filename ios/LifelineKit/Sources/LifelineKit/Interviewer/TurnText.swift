/// Word tokens of spoken text, used to compare what the app said with what the transcriber heard.
public enum TurnText {
    /// Lowercase runs of letters and digits. Inner apostrophes are dropped, so "Maya's" gives "mayas".
    public static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "'" || character == "\u{2019}" {
                continue
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
