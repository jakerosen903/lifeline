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
        let haystack = normalize(segmentText)
        var result = Validated(accepted: [], rejected: [], flags: output.flags)

        for memory in output.memories {
            if let reason = problem(with: memory, haystack: haystack, wordCount: words.count) {
                result.rejected.append(Rejected(candidate: .memory(memory), reason: reason))
            } else {
                result.accepted.append(.memory(memory))
            }
        }
        for mention in output.mentions {
            if contains(haystack, mention.text) {
                result.accepted.append(.mention(mention))
            } else {
                result.rejected.append(Rejected(candidate: .mention(mention), reason: "text not in segment: \(mention.text)"))
            }
        }
        return result
    }

    private static func problem(with memory: MemoryOut, haystack: String, wordCount: Int) -> String? {
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

    /// Substring test after folding case and collapsing whitespace. Empty needles never match.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        let n = normalize(needle)
        return !n.isEmpty && haystack.contains(n)
    }

    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
