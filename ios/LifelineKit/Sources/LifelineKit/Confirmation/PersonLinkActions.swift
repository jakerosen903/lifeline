import Foundation

/// What a move did, enough to take it back exactly. Undo is refused when a row the move left has
/// changed since (`PersonLinkActions.undo`), as `unmerge` does.
public struct PersonMoveReceipt: Sendable, Equatable {
    public var before: [MomentEntity]      // every link row the move touched, as it was
    public var after: [MomentEntity]       // as the move left them
    public var removedPerson: Person?      // an empty guessed person the move removed, with its entity, aliases and first telling
    public var addedAliases: [Alias]
    public var createdPerson: PersonID?    // "Someone new"
    public var newName: String             // for the notice; empty for "Not a person"
    /// The removed person's entity row and aliases, to restore them exactly.
    var removedEntity: Entity?
    var removedAliases: [Alias]
    /// Every span of the persons the move touched, before and after (first tellings, and the removed person's).
    var spansBefore: [EntitySpan]
    var spansAfter: [EntitySpan]
    /// The person whose `created_by_guess` a settle cleared (a move to the same person).
    var clearedGuess: PersonID?

    init(before: [MomentEntity], after: [MomentEntity], removedPerson: Person?, addedAliases: [Alias], createdPerson: PersonID?, newName: String,
         removedEntity: Entity? = nil, removedAliases: [Alias] = [], spansBefore: [EntitySpan] = [], spansAfter: [EntitySpan] = [],
         clearedGuess: PersonID? = nil) {
        self.before = before; self.after = after; self.removedPerson = removedPerson; self.addedAliases = addedAliases
        self.createdPerson = createdPerson; self.newName = newName; self.removedEntity = removedEntity; self.removedAliases = removedAliases
        self.spansBefore = spansBefore; self.spansAfter = spansAfter; self.clearedGuess = clearedGuess
    }
}

/// One said name of a waiting card, as Keep would link it.
public struct PreviewChip: Sendable, Equatable, Identifiable {
    public var saidName: String; public var name: String; public var origin: LinkOrigin; public var person: PersonID?
    public var id: String { SaidName.key(saidName) }

    public init(saidName: String, name: String, origin: LinkOrigin, person: PersonID?) {
        self.saidName = saidName; self.name = name; self.origin = origin; self.person = person
    }
}

/// The sheet (PC2) and the person's page (PC3): the owner settles a guess or moves a name to
/// another person, and can take a move back. Nothing here runs without a tap.
public struct PersonLinkActions: Sendable {
    public enum Error: Swift.Error, Equatable { case stale, notFound }
    public enum Target: Sendable, Equatable { case person(PersonID), someoneNew, notAPerson }

    private let store: ExtractionStore
    /// The contacts Keep's guess may match against, so a preview shows what Keep will do. PC-b sets it.
    public var contactsForGuess: @Sendable () -> [PersonGuess.Contact] = { [] }

    public init(store: ExtractionStore) { self.store = store }

    /// "Yes, this Robyn", and "Done" with the choice unchanged. Origin becomes .confirmed for the link, or its group.
    public func settle(_ link: PersonLink, wholeGroup: Bool) throws {
        try store.personLinks.settle(link, wholeGroup: wholeGroup)
    }

    /// The sheet's "Done" with another choice. One transaction.
    @discardableResult public func move(_ link: PersonLink, to target: Target, wholeGroup: Bool) throws -> PersonMoveReceipt {
        try store.personLinks.move(link, to: target, wholeGroup: wholeGroup)
    }

    public func undo(_ receipt: PersonMoveReceipt) throws {
        try store.personLinks.undo(receipt)
    }

    /// The sheet used on a card that waits: stored, applied on Keep.
    public func choose(_ target: Target, for saidName: String, on candidate: CandidateID) throws {
        try store.personLinks.storeChoice(target, for: saidName, on: candidate)
    }

    /// What Keep would do for each said name of a waiting memory card. Writes nothing.
    /// It runs Keep's own edges (the card and its continuations) for a memory that is never written,
    /// so a chip and the link Keep writes cannot differ: one chip per person, the first said name.
    public func preview(_ candidate: Candidate) throws -> [PreviewChip] {
        guard let out = CandidatePayload.memory(candidate) else { return [] }
        var keep = CandidateActions(store: store)
        keep.contactsForGuess = contactsForGuess
        let unwritten = MemoryID()
        var edges = try keep.edges(of: out, for: unwritten, segment: candidate.segmentID, card: candidate.id)
        for row in try store.candidates.continuations(of: candidate.id) {
            if let o = CandidatePayload.memory(row) { edges.merge(try keep.edges(of: o, for: unwritten, segment: row.segmentID, card: candidate.id)) }
        }
        let planned = Dictionary(edges.entityWrite.persons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try edges.people.compactMap { link in
            // Keep's guess gives every person link its said name and an origin.
            guard let origin = link.origin else { return nil }
            let said = link.roleText ?? ""
            if let new = planned[link.personID] { return PreviewChip(saidName: said, name: new.displayName, origin: origin, person: nil) }
            guard let person = try store.people.person(id: link.personID) else { return nil }
            return PreviewChip(saidName: said, name: person.displayName, origin: origin, person: person.id)
        }
    }
}
