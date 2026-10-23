import Foundation

/// A detail that keeping a memory did not settle. Shown as a word, never as a faded card
/// (decision 2026-10-22: uncertainty is shown, not hidden, and ochre is always paired with text).
public enum CheckThis: Equatable, Sendable {
    /// An inferred range, with its display text.
    case range(String)
    /// A name the app could not place, with the mention that asks about it.
    case person(name: String, mention: MentionID)
    /// The extractor itself was unsure about this suggestion.
    case lowConfidence

    public var label: String {
        switch self {
        case .range(let text): "Check this: \(text)?"
        case .person(let name, _): "Check this: \(name)?"
        case .lowConfidence: "Check this"
        }
    }
}

public enum CheckThisTags {
    public static let lowConfidenceBelow = 0.5

    /// The range first when it is a guess, then one tag per open name (deduplicated by the
    /// name as the app normalizes it), then the extractor's own doubt.
    public static func tags(range: TimeRange, mentions: [Mention], confidence: Double? = nil,
                            lowConfidenceBelow threshold: Double = CheckThisTags.lowConfidenceBelow) -> [CheckThis] {
        var out: [CheckThis] = []
        if range.isPlaced, range.origin == .inferred { out.append(.range(range.displayText)) }
        var seen = Set<String>()
        for mention in mentions where mention.status == .unresolved {
            let key = PeopleRepository.normalize(mention.text)
            if seen.insert(key).inserted { out.append(.person(name: mention.text, mention: mention.id)) }
        }
        if let confidence, confidence < threshold { out.append(.lowConfidence) }
        return out
    }
}
