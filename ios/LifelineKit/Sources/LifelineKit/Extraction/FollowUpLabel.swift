import Foundation

/// Pure: the words on a follow-up chip, before and after it is answered.
public enum FollowUpLabel {
    /// The open chip: "Family?", "Story: the steak dinner?", "the shed: a place?".
    public static func question(_ followUp: Card) -> String {
        switch followUp {
        case .hint(_, let hint):
            hint.kind == .domain ? capitalized(hint.phrase) + "?" : "\(prefix(hint.kind)): \(hint.phrase)?"
        case .entity(_, let m):
            suffixed(m)
        case .whoIsThis(_, let text):
            "\(text): who's this?"
        case .memory(_, let out):
            out.title
        }
    }

    /// The answered chip: a checkmark and the plain text.
    public static func done(_ followUp: Card) -> String {
        "✓ " + plain(followUp)
    }

    private static func plain(_ followUp: Card) -> String {
        switch followUp {
        case .hint(_, let hint):
            hint.kind == .domain ? capitalized(hint.phrase) : "\(prefix(hint.kind)): \(hint.phrase)"
        case .entity(_, let m): m.kind == .idea ? (m.title ?? m.text) : m.text
        case .whoIsThis(_, let text): text
        case .memory(_, let out): out.title
        }
    }

    private static func suffixed(_ m: MentionOut) -> String {
        switch m.kind {
        case .thing: "\(m.text): a thing?"
        case .place: "\(m.text): a place?"
        case .idea: "\(m.title ?? m.text): something you think?"
        case .person: "\(m.text): who's this?"
        }
    }

    private static func prefix(_ kind: HintKind) -> String {
        switch kind {
        case .story: "Story"
        case .collection: "Collection"
        case .chapter: "Chapter"
        case .domain: ""
        }
    }

    private static func capitalized(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }
}
