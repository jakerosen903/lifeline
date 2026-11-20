import Foundation

/// Pure: whether a memory card carries a person card's name. Keep links a carried name itself
/// (`PersonGuess`), so the person card must ask nothing, or an answer would add a second link.
/// A group phrase ("our parents") is never carried: it keeps its own question.
public enum CarriedName {
    /// The memory carries the mention's handle (v8), says the name as a whole ref or as the name
    /// part of a comma ref ("my roommate, Robin"), or is a fact about the mention's `ref`.
    /// A handle no memory carries, or one no `people` entry has, falls through to the name rules.
    public static func carries(_ memory: MemoryOut, _ mention: MentionOut) -> Bool {
        guard mention.kind == .person, !GroupPhrase.isGroup(mention.text) else { return false }
        if let handle = mention.handle, memory.personHandles.contains(handle) { return true }
        if let ref = mention.ref, memory.aboutRef == ref { return true }
        let key = SaidName.key(mention.text)
        guard !key.isEmpty else { return false }
        return memory.peopleRefs.contains { SaidName.key($0) == key || SaidName(ref: $0).name.map(SaidName.key) == key }
    }
}
