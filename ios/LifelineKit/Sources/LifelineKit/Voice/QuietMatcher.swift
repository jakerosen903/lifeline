/// Hears a request in what the person said, on the device. The voice session passes the person's
/// words of one final. A request is short: a phrase counts only in a few words, so
/// "my father would never let me talk back" is a story, not a request.
public enum QuietMatcher {
    /// The most tokens that can be a request.
    static let maxTokens = 4

    private static let phrases: [(tokens: [String], command: VoiceCommand)] = [
        (["let", "me", "talk"], .quiet),
        (["quiet", "please"], .quiet),
        (["stop", "talking"], .quiet),
        (["no", "questions"], .quiet),
        (["keep", "going"], .keepGoing),
        (["a", "bit", "more"], .keepGoing),
    ]

    /// The request in `partial` (the person's words): a phrase as consecutive tokens, or any "shh" ("sh", "shhhh").
    public static func command(in partial: String) -> VoiceCommand? {
        let tokens = TurnText.tokens(partial)
        guard !tokens.isEmpty, tokens.count <= maxTokens else { return nil }
        if tokens.contains(where: isShh) { return .quiet }
        return phrases.first { contains(tokens, run: $0.tokens) }?.command
    }

    /// `^sh+$`.
    private static func isShh(_ token: String) -> Bool {
        token.count >= 2 && token.hasPrefix("s") && token.dropFirst().allSatisfy { $0 == "h" }
    }

    private static func contains(_ tokens: [String], run: [String]) -> Bool {
        guard run.count <= tokens.count else { return false }
        return (0...(tokens.count - run.count)).contains { Array(tokens[$0..<$0 + run.count]) == run }
    }
}
