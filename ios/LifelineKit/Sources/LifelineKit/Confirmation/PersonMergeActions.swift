import Foundation

/// What the confirm sheet shows. Made by `check`, which throws every refusal before the owner is asked.
public struct PersonMergePreview: Sendable, Equatable {
    public var leaving: Person
    public var staying: Person
    /// Plan decision 1: true when the result is hidden and the two differed.
    public var staysHidden: Bool
    /// Plan decision 1: true when the result is kept from the AI and the two differed.
    public var staysOutOfAI: Bool

    public init(leaving: Person, staying: Person, staysHidden: Bool, staysOutOfAI: Bool) {
        self.leaving = leaving; self.staying = staying; self.staysHidden = staysHidden; self.staysOutOfAI = staysOutOfAI
    }
}

/// What a merge did. Task 3 adds the rows before and after, so Undo can put them back.
public struct PersonMergeReceipt: Sendable, Equatable {
    public var staying: PersonID
    public var leaving: PersonID
    /// The staying person's name, for the notice "Merged into {name}.".
    public var stayingName: String
}

/// Two people who are one real person (spec "Merging two people"): the person the owner picks stays, and the other
/// joins them. Nothing here runs without the owner's tap on "Merge".
public struct PersonMergeActions: Sendable {
    public enum Error: Swift.Error, Equatable { case samePerson, notFound, owner, twoContacts, stale }

    private let store: ExtractionStore

    public init(store: ExtractionStore) { self.store = store }

    /// Every person but this one and the owner, most recently linked first. The picker lists these (plan decision 5).
    public func others(than person: PersonID) throws -> [Person] {
        try store.people.peopleByRecentLink().filter { $0.id != person }
    }

    /// What the confirm sheet shows. Writes nothing. Throws the refusals `merge` throws.
    public func check(_ leaving: PersonID, into staying: PersonID) throws -> PersonMergePreview {
        try store.personLinks.checkMerge(leaving, into: staying)
    }

    /// One transaction: `leaving` joins `staying` and is deleted. A kill leaves the old state or the new one.
    @discardableResult public func merge(_ leaving: PersonID, into staying: PersonID) throws -> PersonMergeReceipt {
        try store.personLinks.merge(leaving, into: staying)
    }
}
