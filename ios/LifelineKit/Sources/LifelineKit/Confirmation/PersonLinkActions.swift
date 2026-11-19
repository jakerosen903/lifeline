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
    /// The person whose `created_by_guess` the action cleared, with their name as it was then.
    var clearedGuess: PersonName?
    /// The "Someone new" person's name as made. Undo refuses to delete them after a rename.
    var createdName: PersonName?
    /// The page links of the story's photo that followed the name. Nil: the move touched no photo link.
    public var photoPages: PhotoPageChange?
    /// The removed person's link to the picture the app copied from their contact (PB12), to put it back.
    var removedContactPhoto: ContactPhotoLink?

    /// A person's name and where it came from, so Undo can tell the owner renamed them since.
    struct PersonName: Sendable, Equatable {
        var id: PersonID; var name: String; var origin: NameOrigin?
    }

    /// The contact's copied picture as the removed person's page held it. The role is the stored text, kept
    /// as it was, so Undo writes back exactly what the move took away.
    struct ContactPhotoLink: Sendable, Equatable {
        var photo: PhotoID; var role: String; var sortOrder: Int
    }

    init(before: [MomentEntity], after: [MomentEntity], removedPerson: Person?, addedAliases: [Alias], createdPerson: PersonID?, newName: String,
         removedEntity: Entity? = nil, removedAliases: [Alias] = [], spansBefore: [EntitySpan] = [], spansAfter: [EntitySpan] = [],
         clearedGuess: PersonName? = nil, createdName: PersonName? = nil, photoPages: PhotoPageChange? = nil,
         removedContactPhoto: ContactPhotoLink? = nil) {
        self.before = before; self.after = after; self.removedPerson = removedPerson; self.addedAliases = addedAliases
        self.createdPerson = createdPerson; self.newName = newName; self.removedEntity = removedEntity; self.removedAliases = removedAliases
        self.spansBefore = spansBefore; self.spansAfter = spansAfter; self.clearedGuess = clearedGuess; self.createdName = createdName
        self.photoPages = photoPages
        self.removedContactPhoto = removedContactPhoto
    }
}

/// How a move of a name changed the page links of its story's photo, so Undo can take it back.
public struct PhotoPageChange: Sendable, Equatable {
    public var photo: PhotoID
    public var added: [EntityID]        // pages the move put the photo on (origin `story`)
    public var removed: [EntityID]      // pages the move took the story's link from
}

/// One said name of a waiting card, as Keep would link it, or as the owner marked it "Not a person".
public struct PreviewChip: Sendable, Equatable, Identifiable {
    public var saidName: String; public var name: String; public var origin: LinkOrigin; public var person: PersonID?
    /// The owner marked this name "Not a person": Keep links nothing, and the quiet chip reopens the sheet (R37).
    public var isNotAPerson: Bool
    /// Keep will make the person from a contact, or did in this recording (`PersonLink.personFromContact`).
    public var fromContact: Bool
    /// The contact Keep will make the person from, when Keep makes a person (`person` nil). The sheet opens on it,
    /// so "Done" with nothing changed keeps that contact (I-1). Nil for a person on file or a person with no contact.
    public var contactIdentifier: String?
    /// The extractor's handle for this person (PC-d); nil for a card from before v8. The sheet's answer is stored
    /// under it, so two chips of one said name are two answers.
    public var handle: String?
    /// The key the sheet's answer for this chip is stored under (`ChoiceKey`).
    public var id: String { ChoiceKey.text(saidName: saidName, handle: handle) }

    public init(saidName: String, name: String, origin: LinkOrigin, person: PersonID?, fromContact: Bool = false,
                contactIdentifier: String? = nil, handle: String? = nil) {
        self.saidName = saidName; self.name = name; self.origin = origin; self.person = person
        self.isNotAPerson = false; self.fromContact = fromContact; self.contactIdentifier = contactIdentifier; self.handle = handle
    }

    /// The chip shows the said name with no line and no mark: the owner's own answer (`confirmed`).
    public static func notAPerson(saidName: String, handle: String? = nil) -> PreviewChip {
        var chip = PreviewChip(saidName: saidName, name: saidName.trimmingCharacters(in: .whitespacesAndNewlines), origin: .confirmed, person: nil,
                               handle: handle)
        chip.isNotAPerson = true
        return chip
    }
}

/// The sheet (PC2) and the person's page (PC3): the owner settles a guess or moves a name to
/// another person, and can take a move back. Nothing here runs without a tap.
public struct PersonLinkActions: Sendable {
    public enum Error: Swift.Error, Equatable { case stale, notFound }
    /// `contact`: the person who holds that contact, or a new person made from it (`Person.fromContact`).
    public enum Target: Sendable, Equatable { case person(PersonID), someoneNew, notAPerson, contact(ContactCard) }

    private let store: ExtractionStore
    /// The contacts Keep's guess may match against, so a preview shows what Keep will do.
    public var contactsForGuess: @Sendable () -> [PersonGuess.Contact] = { [] }

    public init(store: ExtractionStore) { self.store = store }

    /// "Yes, this Robyn", and "Done" with the choice unchanged. Origin becomes .confirmed for the link, or its group.
    public func settle(_ link: PersonLink, wholeGroup: Bool) throws {
        try store.personLinks.settle(link, wholeGroup: wholeGroup)
    }

    /// The sheet's "Done" with another choice. One transaction. A contact a person holds is a move to that person;
    /// a contact no one holds makes a person the owner chose, and Undo removes them.
    @discardableResult public func move(_ link: PersonLink, to target: Target, wholeGroup: Bool) throws -> PersonMoveReceipt {
        try store.personLinks.move(link, to: target, wholeGroup: wholeGroup)
    }

    public func undo(_ receipt: PersonMoveReceipt) throws {
        try store.personLinks.undo(receipt)
    }

    /// The sheet used on a card that waits: stored, applied on Keep. A contact a person holds is stored as that person.
    /// `handle`: the chip's handle (`PreviewChip.handle`), so the answer reaches that handle only.
    public func choose(_ target: Target, for saidName: String, handle: String? = nil, on candidate: CandidateID) throws {
        try store.personLinks.storeChoice(target, for: saidName, handle: handle, on: candidate)
    }

    /// What Keep would do for each said name of a waiting memory card. Writes nothing.
    /// It runs Keep's own edges (the card and its continuations) for a memory that is never written,
    /// so a chip and the link Keep writes cannot differ: one chip per person, the first said name.
    public func preview(_ candidate: Candidate) throws -> [PreviewChip] {
        guard let out = CandidatePayload.memory(candidate) else { return [] }
        var keep = CandidateActions(store: store)
        keep.contactsForGuess = contactsForGuess
        let continuations = try store.candidates.continuations(of: candidate.id)
        let edges = try keep.tellingEdges(of: out, card: candidate, continuations: continuations, for: MemoryID())
        let planned = Dictionary(edges.entityWrite.persons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recording = try store.sessions.fetchSegment(candidate.segmentID)?.sessionID
        let linked: [PreviewChip] = try edges.people.compactMap { link in
            // Keep's guess gives every person link its said name and an origin.
            guard let origin = link.origin else { return nil }
            let said = link.roleText ?? ""
            if let new = planned[link.personID] {
                return PreviewChip(saidName: said, name: new.displayName, origin: origin, person: nil, fromContact: new.isGuessFromContact,
                                   contactIdentifier: new.contactIdentifier, handle: link.handle)
            }
            guard let person = try store.people.person(id: link.personID) else { return nil }
            // As `PersonLink.personFromContact`: only in the recording of the person's first link (PB11).
            let first = try store.personLinks.firstSession(of: person.id)
            let fromContact = person.isGuessFromContact && (first == nil || first == recording)
            return PreviewChip(saidName: said, name: person.displayName, origin: origin, person: person.id, fromContact: fromContact,
                               handle: link.handle)
        }
        // A card with handles names its people by handle; an older card by said name alone.
        let names = ([out] + continuations.compactMap(CandidatePayload.memory)).flatMap { o -> [(saidName: String, handle: String?)] in
            o.handlePeople.isEmpty ? o.peopleRefs.map { ($0, nil) } : o.handlePeople.map { ($0.saidName, $0.handle) }
        }
        return Self.withNotAPerson(linked, names: names, choices: try store.personLinks.choices(for: candidate.id))
    }

    /// Keep's chips, with a quiet chip for each said name the owner marked "Not a person", in the order
    /// the names were said. A sheet opens only from a chip, so a stored "Not a person" always had one.
    /// Names and answers meet by `ChoiceKey`: with a handle, a mark reaches that handle only.
    static func withNotAPerson(_ linked: [PreviewChip], names: [(saidName: String, handle: String?)], choices: [PersonChoice]) -> [PreviewChip] {
        let marked = Set(choices.filter(\.notAPerson).map(\.saidKey))
        guard !marked.isEmpty else { return linked }
        var out: [PreviewChip] = [], seen = Set<String>(), rest = linked
        for name in names {
            let key = ChoiceKey.text(saidName: name.saidName, handle: name.handle)
            guard !SaidName.key(name.saidName).isEmpty, seen.insert(key).inserted else { continue }
            if let index = rest.firstIndex(where: { $0.id == key }) {
                out.append(rest.remove(at: index))
            } else if marked.contains(key) {
                out.append(.notAPerson(saidName: name.saidName, handle: name.handle))
            }
        }
        return out + rest   // a chip whose said name is not among the names keeps Keep's order at the end
    }
}
