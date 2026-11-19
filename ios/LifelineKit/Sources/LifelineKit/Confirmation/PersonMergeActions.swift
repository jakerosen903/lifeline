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

/// What a merge did, with the rows before and after, so Undo can put them back. It lives in memory only (plan decision 7).
public struct PersonMergeReceipt: Sendable, Equatable {
    public var staying: PersonID
    public var leaving: PersonID
    /// The staying person's name, for the notice "Merged into {name}.".
    public var stayingName: String

    /// The rows of both persons in the owned tables, read before any change.
    var before: [RowCopy]
    /// The rows of the staying person in the same tables, as the merge left them. Undo compares them first.
    var after: [RowCopy]
    /// The staying person's person and entity rows, before and after the merge.
    var personBefore: RowCopy, personAfter: RowCopy
    var entityBefore: RowCopy, entityAfter: RowCopy
    /// The leaving person's person and entity rows, which the merge deleted.
    var leavingPerson: RowCopy, leavingEntity: RowCopy
    /// Table name to the keys of the rows the merge pointed at the staying person.
    var repointed: [String: [String]]
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

    /// One transaction: both people are back, every row as it was before the merge. Throws `.stale`, and changes
    /// nothing, when a row the merge left has changed since.
    public func undo(_ receipt: PersonMergeReceipt) throws {
        try store.personLinks.undoMerge(receipt)
    }
}
