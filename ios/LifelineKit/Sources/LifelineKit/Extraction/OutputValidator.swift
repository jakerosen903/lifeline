import Foundation

/// Checks the extractor's output against the segment before anything is stored or shown.
/// Every content field must be the owner's words: a quote, a name, a phrase copied from the
/// segment. The title is composed by the model and is only checked for length. Nothing here
/// touches the network or the store.
public enum OutputValidator {
    public enum ValidatedCandidate: Sendable, Equatable {
        case memory(MemoryOut)
        case mention(MentionOut)
    }

    public struct Rejected: Sendable, Equatable {
        public let candidate: ValidatedCandidate
        public let reason: String
    }

    public struct Validated: Sendable, Equatable {
        public var accepted: [ValidatedCandidate]
        public var rejected: [Rejected]
        public var flags: Flags
    }

    public static let maxTitleWords = 8

    public static func validate(_ output: ExtractorOutput, segmentText: String, words: [String]) -> Validated {
        let haystack = tokens(segmentText)
        var result = Validated(accepted: [], rejected: [], flags: output.flags)

        for var memory in output.memories {
            // A place, thing or idea the segment does not name is dropped, not the memory with it (M7).
            memory.entityRefs = memory.entityRefs.filter { contains(haystack, $0.text) }
            if let reason = problem(with: memory, haystack: haystack, wordCount: words.count) {
                result.rejected.append(Rejected(candidate: .memory(memory), reason: reason))
            } else {
                result.accepted.append(.memory(memory))
            }
        }
        for var mention in output.mentions {
            if contains(haystack, mention.text) {
                // An idea's title must be the person's words; anything else gives way to the dated default (M7).
                if mention.kind == .idea { mention.title = IdeaTitle.verbatim(mention.title, in: segmentText) }
                result.accepted.append(.mention(mention))
            } else {
                result.rejected.append(Rejected(candidate: .mention(mention), reason: "text not in segment: \(mention.text)"))
            }
        }
        return result
    }

    private static func problem(with memory: MemoryOut, haystack: [String], wordCount: Int) -> String? {
        if !contains(haystack, memory.quote) { return "quote not in segment" }
        let span = memory.segmentSpan
        if span.startWord < 0 || span.endWord >= wordCount || span.startWord > span.endWord {
            return "segment_span \(span.startWord)...\(span.endWord) outside 0..<\(wordCount)"
        }
        if let ref = memory.peopleRefs.first(where: { !contains(haystack, $0) }) { return "people_refs not in segment: \(ref)" }
        if let place = memory.placeText, !contains(haystack, place) { return "place_text not in segment: \(place)" }
        if let anchor = memory.anchors.first(where: { !contains(haystack, $0.phrase) }) { return "anchors phrase not in segment: \(anchor.phrase)" }
        if memory.title.split(whereSeparator: \.isWhitespace).count > maxTitleWords { return "title longer than \(maxTitleWords) words" }
        return nil
    }

    /// True when the needle's words appear in the haystack as a run of whole words. Matching on
    /// words, not characters, keeps "Al" from matching "always". Case, surrounding punctuation
    /// and curly apostrophes are folded. Empty needles never match.
    static func contains(_ haystack: [String], _ needle: String) -> Bool {
        let n = tokens(needle)
        guard !n.isEmpty, n.count <= haystack.count else { return false }
        return (0...(haystack.count - n.count)).contains { start in
            Array(haystack[start..<(start + n.count)]) == n
        }
    }

    /// Convenience for callers holding the segment text.
    public static func contains(_ haystack: String, _ needle: String) -> Bool {
        contains(tokens(haystack), needle)
    }

    /// Lowercased words with edge punctuation removed and apostrophes unified.
    public static func tokens(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { String($0.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "'")))) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    public static func normalize(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }
}
