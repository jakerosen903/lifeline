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

    /// The output without the owner as a person: person mentions, `people` entries (with their
    /// handles on each memory) and `people_refs` that are the owner's name go, and a fact that was
    /// about such a mention or handle is about `self`. The memory itself stays. Everything else
    /// is returned as it came. The prompt asks for the same; the code does not rely on it.
    public func removingOwner(from validated: OutputValidator.Validated) -> OutputValidator.Validated {
        guard !keys.isEmpty else { return validated }
        var out = validated
        let ownerHandles = Set(validated.people.filter { isOwner($0.saidName, relation: $0.relationText) }.map(\.handle))
        out.people = validated.people.filter { !ownerHandles.contains($0.handle) }
        var ownerRefs = ownerHandles
        out.accepted = validated.accepted.filter { candidate in
            guard case .mention(let mention) = candidate, mention.kind == .person else { return true }
            // A mention said another way ("me") but tied to the owner's handle is the owner too.
            guard isOwner(mention.text, relation: mention.relationText) || mention.handle.map(ownerHandles.contains) == true else { return true }
            if let ref = mention.ref { ownerRefs.insert(ref) }
            return false
        }
        out.accepted = out.accepted.map { candidate in
            guard case .memory(var memory) = candidate else { return candidate }
            memory.peopleRefs = memory.peopleRefs.filter { !isOwner($0) }
            memory.personHandles = memory.personHandles.filter { !ownerHandles.contains($0) }
            if let about = memory.aboutRef, ownerRefs.contains(about) { memory.aboutRef = "self" }
            return .memory(memory)
        }
        return out
    }
}
