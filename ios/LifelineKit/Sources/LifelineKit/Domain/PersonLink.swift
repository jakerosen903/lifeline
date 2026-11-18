import Foundation

/// One link between a memory and a person, as the views read it: the person, the name the owner
/// said for this memory, and how the link was made. `origin` is nil for a link older than v14.
public struct PersonLink: Sendable, Equatable, Identifiable {
    public var memoryID: MemoryID
    public var person: Person
    public var saidName: String?
    public var origin: LinkOrigin?
    public var relation: EntityRelation

    public init(memoryID: MemoryID, person: Person, saidName: String?, origin: LinkOrigin?, relation: EntityRelation) {
        self.memoryID = memoryID; self.person = person; self.saidName = saidName
        self.origin = origin; self.relation = relation
    }

    public var id: String { "\(memoryID.rawValue)|\(person.id.rawValue)|\(relation.rawValue)" }

    /// A guess the owner has not seen. It carries the ochre mark.
    public var isGuess: Bool { origin == .assumed }
}
