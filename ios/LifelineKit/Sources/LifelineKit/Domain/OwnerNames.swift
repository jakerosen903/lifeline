import Foundation

/// The names the app knows the owner by, as match keys. The speaker is the owner, so the owner's
/// own name in a story is not a person to ask about (audit F10).
public struct OwnerNames: Sendable, Equatable {
    public let keys: Set<String>

    /// Empty names are ignored: an owner with no typed name has no keys and matches nobody.
    public init(names: [String]) {
        keys = Set(names.map(MatchKey.of).filter { !$0.isEmpty })
    }

    /// True when `text` is one of the owner's names. A name said with a relation ("my cousin
    /// Jordan") is someone else who shares the name, so it is never the owner.
    public func isOwner(_ text: String, relation: String? = nil) -> Bool {
        guard relation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return false }
        let key = MatchKey.of(text)
        return !key.isEmpty && keys.contains(key)
    }

    /// The output without the owner as a person: person mentions and `people_refs` that are the
    /// owner's name go, and a fact that was about such a mention is about `self`. Everything else
    /// is returned as it came. The prompt asks for the same; the code does not rely on it.
    public func removingOwner(from validated: OutputValidator.Validated) -> OutputValidator.Validated {
        guard !keys.isEmpty else { return validated }
        var out = validated
        var ownerRefs = Set<String>()
        out.accepted = validated.accepted.filter { candidate in
            guard case .mention(let mention) = candidate, mention.kind == .person, isOwner(mention.text, relation: mention.relationText) else { return true }
            if let ref = mention.ref { ownerRefs.insert(ref) }
            return false
        }
        out.accepted = out.accepted.map { candidate in
            guard case .memory(var memory) = candidate else { return candidate }
            memory.peopleRefs = memory.peopleRefs.filter { !isOwner($0) }
            if let about = memory.aboutRef, ownerRefs.contains(about) { memory.aboutRef = "self" }
            return .memory(memory)
        }
        return out
    }
}
