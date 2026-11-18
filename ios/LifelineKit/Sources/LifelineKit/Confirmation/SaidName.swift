import Foundation

/// A name as the owner said it: "Marcel", "my mom", or "my mom, Marcel". Pure parsing. The
/// owner's words stay as spoken in `raw`; `name` and `relation` are the two parts.
public struct SaidName: Sendable, Equatable {
    public var name: String?        // "Marcel"; nil when only a relation phrase was said
    public var relation: String?    // "my mom"
    public var raw: String          // the ref as the extractor gave it

    /// `mentionRelation` is the relation_text of a person mention in the same segment with this text.
    public init(ref: String, mentionRelation: String? = nil) {
        raw = ref
        let all = PeopleRepository.parts(of: ref)
        let parts = all.count > 1 ? Array(all.dropFirst()) : all   // drop the whole phrase when it was split
        let relationPart = parts.first(where: Self.isRelation)
        let namePart = parts.first { !Self.isRelation($0) && !Self.key($0).isEmpty }
        name = namePart
        let mention = mentionRelation.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        relation = relationPart ?? mention.flatMap { Self.isRelation($0) ? $0 : nil }
    }

    /// Lowercased, trimmed, diacritics folded. The key every comparison in this feature uses.
    public static func key(_ text: String) -> String {
        MatchKey.of(text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
    }

    /// The key of the whole text and of each comma part. "my mom, Marcel" -> ["my mom, marcel", "my mom", "marcel"].
    static func keyParts(of text: String) -> [String] {
        PeopleRepository.parts(of: text).map(key).filter { !$0.isEmpty }
    }

    /// A relation phrase starts with "my " or "our ".
    static func isRelation(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("my ") || lower.hasPrefix("our ")
    }
}
