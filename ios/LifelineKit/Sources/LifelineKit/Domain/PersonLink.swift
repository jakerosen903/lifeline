import Foundation

/// One link between a memory and a person, as the views read it: the person, the name the owner
/// said for this memory, and how the link was made. `origin` is nil for a link older than v15.
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

extension PersonLink {
    /// The guesses among a person's links, one for each memory. Only `assumed` links count. A memory with
    /// a guessed mention and a guessed detail gives the mention link, so one memory shows one pair of answers.
    public static func guesses(among links: [PersonLink]) -> [MemoryID: PersonLink] {
        var found: [MemoryID: PersonLink] = [:]
        for link in links where link.isGuess {
            if let have = found[link.memoryID], have.relation == .mention { continue }
            found[link.memoryID] = link
        }
        return found
    }
}
