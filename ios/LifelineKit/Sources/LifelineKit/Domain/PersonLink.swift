import Foundation

/// One link between a memory and a person, as the views read it: the person, the name the owner
/// said for this memory, and how the link was made. `origin` is nil for a link older than v15.
public struct PersonLink: Sendable, Equatable, Identifiable {
    public var memoryID: MemoryID
    public var person: Person
    public var saidName: String?
    public var origin: LinkOrigin?
    public var relation: EntityRelation
    /// The extractor's handle for the person in the link's recording (PC-d). Nil for a link older than v8, a link the
    /// owner made by hand, and a Same story into another recording's memory (D11).
    public var handle: String?

    /// The link's memory was told in the same recording as the person's first link (PB11).
    public var inPersonsFirstRecording: Bool

    public init(memoryID: MemoryID, person: Person, saidName: String?, origin: LinkOrigin?, relation: EntityRelation,
                inPersonsFirstRecording: Bool = true, handle: String? = nil) {
        self.memoryID = memoryID; self.person = person; self.saidName = saidName
        self.origin = origin; self.relation = relation; self.inPersonsFirstRecording = inPersonsFirstRecording; self.handle = handle
    }

    public var id: String { "\(memoryID.rawValue)|\(person.id.rawValue)|\(relation.rawValue)" }

    /// A guess the owner has not seen. It carries the ochre mark.
    public var isGuess: Bool { origin == .assumed }

    /// The person is one Keep made from a contact, the owner has not yet stood behind them (rules 3 and 5),
    /// and this link is in the recording that made them. In a later recording they are not new (PB11).
    public var personFromContact: Bool { person.isGuessFromContact && inPersonsFirstRecording }
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
