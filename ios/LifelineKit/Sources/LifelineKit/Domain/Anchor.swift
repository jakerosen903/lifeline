import Foundation

public enum AnchorRelation: String, Codable, Sendable, CaseIterable {
    case before, after, during, sameYearAs = "same_year_as", age, absolute
}

public enum AnchorTargetKind: String, Codable, Sendable {
    case memory, personBirth = "person_birth", chapter, publicEvent = "public_event", none
}

/// A typed edge from a memory to what it is relative to, in the owner's phrase.
/// M2 stores anchors unresolved; the resolver (M3) sets ranges from them.
public struct Anchor: Codable, Sendable, Equatable, Identifiable {
    public var id: AnchorID
    public var memoryID: MemoryID
    public var phrase: String
    public var relation: AnchorRelation
    public var targetKind: AnchorTargetKind
    public var targetID: String?
    /// The owner's phrase for what this is relative to ("graduation", "the Boston years"), or nil.
    public var targetText: String?
    /// The relation's value as the extractor gave it (a stated date, an age); nil when the phrase is all there is.
    public var value: String?
    public var resolved: Bool

    public init(id: AnchorID, memoryID: MemoryID, phrase: String, relation: AnchorRelation, targetKind: AnchorTargetKind,
                targetID: String?, targetText: String? = nil, value: String?, resolved: Bool) {
        self.id = id; self.memoryID = memoryID; self.phrase = phrase; self.relation = relation; self.targetKind = targetKind
        self.targetID = targetID; self.targetText = targetText; self.value = value; self.resolved = resolved
    }
}
