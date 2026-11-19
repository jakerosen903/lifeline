import Foundation
import Synchronization

/// The check of linked contacts, the suggestion of a contact, and the look again after access (spec, "The identifier",
/// "A contact that changes", "A contact that appears later (PC4)", "When the guess is made").
extension ContactLinkActions {
    /// Runs at launch and when the system says contacts changed. Reads only the linked identifiers; reads all contacts
    /// once, only under full access and only when an identifier does not resolve. Without access it changes nothing: the app cannot tell a deleted
    /// contact from one it may not see (Review Focus 4). A failed read of the cards throws before anything is written;
    /// a picture that cannot be read or stored is skipped, and the next check tries again (PB16).
    public func check() async throws {
        let access = directory.access()
        switch access {
        case .notAsked, .denied: return
        case .full, .limited: break
        }
        let linked = try store.people.linkedPersons()
        guard !linked.isEmpty else { return }
        let found = try await directory.cards(identifiers: linked.compactMap(\.contactIdentifier))
        var missing: [(person: Person, stored: String)] = []
        for person in linked {
            guard let stored = person.contactIdentifier else { continue }
            if let card = try await card(for: stored, in: found) {
                try await follow(person.id, from: stored, to: card)
            } else {
                missing.append((person, stored))
            }
        }
        guard !missing.isEmpty else { return }
        // Under limited access the app sees only the shared contacts, so a card with the kept name may be a namesake
        // and the contact may only be unshared: the person keeps everything and shows as missing (PB34).
        guard access == .full else {
            for (person, stored) in missing { try store.people.markContactMissing(person.id, from: stored) }
            return
        }
        let visible = try await directory.all()
        var held = Set(try store.people.linkedPersons().compactMap(\.contactIdentifier))
        for (person, stored) in missing {
            if let keptName = person.contactName, let card = Self.nameMatch(keptName, in: visible, held: held) {
                held.insert(card.identifier)
                try await follow(person.id, from: stored, to: card)
            } else {
                try store.people.markContactMissing(person.id, from: stored)
            }
        }
    }

    /// The card for a stored identifier: from the batch read, or, when the batch has no card with that identifier,
    /// from a read of that identifier alone, which gives the card the system unified it into (and its new identifier).
    private func card(for stored: String, in found: [ContactCard]) async throws -> ContactCard? {
        if let card = found.first(where: { $0.identifier == stored }) { return card }
        return try await directory.cards(identifiers: [stored]).first
    }

    /// The one visible contact, not held by a person, whose full name equals the kept name. Nil for none or several.
    static func nameMatch(_ keptName: String, in visible: [ContactCard], held: Set<String>) -> ContactCard? {
        let key = SaidName.key(keptName)
        guard !key.isEmpty else { return nil }
        let fits = visible.filter { !held.contains($0.identifier) && SaidName.key($0.fullName) == key }
        return fits.count == 1 ? fits[0] : nil
    }

    private func follow(_ id: PersonID, from stored: String, to card: ContactCard) async throws {
        guard try store.people.followContact(id, from: stored, to: card) == .followed,
              let person = try store.people.person(id: id) else { return }
        if person.contactPhotoID == nil {
            try? await copyPicture(for: id)
        } else {
            try? await replacePicture(of: person)
        }
    }

    /// "New picture" (plan decision 10): only while the app's copy is the person's first photo. The same bytes as a
    /// stored photo change nothing: the copy itself means the picture did not change, and the owner's photo is never
    /// claimed as the copy. A contact with no picture now keeps the copy: "New picture" asks for a picture. The new
    /// photo, its link, the record and the old copy's removal are one transaction; the old file goes after the commit
    /// (a kill before that leaves a file with no row, which the launch sweep takes).
    private func replacePicture(of person: Person) async throws {
        guard let identifier = person.contactIdentifier, let copy = person.contactPhotoID,
              try store.photos.photos(of: .entity(person.entityID)).first?.id == copy,
              let data = try await directory.picture(identifier: identifier), !data.isEmpty else { return }
        let file = try pictureFile(data)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        guard try store.photos.photo(sha256: try PhotoImport.sha256(of: file)) == nil else { return }
        let gone = Mutex<Photo?>(nil)
        do {
            // A photo with these bytes stored between the read above and this call is linked, not recorded: the copy stays.
            _ = try await photos.addRecordingNew(fileAt: file, to: .entity(person.entityID)) { db, new in
                let removed = try PeopleRepository.replaceContactPhoto(copy, with: new, for: person.id, identifier: identifier, in: db)
                gone.withLock { $0 = removed }
            }
        } catch is PeopleRepository.ContactChangedDuringCopy {
            return
        }
        if let removed = gone.withLock({ $0 }) { await photos.removeFile(of: removed) }
    }

    /// The contact offered on a person's page, from the cards the app can see. Nil for the owner and for a person
    /// with a contact (a missing one included).
    public func suggestion(for person: PersonID, in cards: [ContactCard]) throws -> ContactCard? {
        guard let found = try store.people.person(id: person), !found.isOwner, found.contactIdentifier == nil else { return nil }
        return ContactSuggestion.pick(name: found.displayName, aliases: try store.people.aliases(of: person).map(\.text), cards: cards,
                                      linked: Set(try store.people.linkedPersons().compactMap(\.contactIdentifier)),
                                      declined: try store.people.declinedContacts(of: person))
    }

    /// "No, someone else": `card` is not offered for this person again.
    public func decline(_ card: ContactCard, for person: PersonID) throws {
        try store.people.declineContact(card.identifier, for: person)
    }

    /// Plan decision 7: after access is given on a recording's landing, a look again at that recording only. For each
    /// person the app made there from a said name (`created_by_guess`, `name_origin` said, no contact) with a `new`
    /// link: the guess runs again for that link's said name, against the other people on file and `contacts`. When it
    /// picks one contact (rule 5, or rule 3's contact) that the owner has not declined for that person (PB35), the app links the person to it and the person's `new` links in
    /// the session become `assumed`. Returns the links changed and the people linked. Pictures are not read here: the
    /// caller copies them for `linkedPeople`.
    @discardableResult
    public func reguess(session: SessionID, contacts: [PersonGuess.Contact]) async throws -> Reguess {
        var seen = Set<PersonID>()
        var changed = 0
        var linked: [PersonID] = []
        for link in try store.personLinks.newMentionLinks(in: session) {
            let person = link.person
            guard !seen.contains(person.id), !person.isOwner, person.createdByGuess, person.nameOrigin == .said,
                  person.contactIdentifier == nil, let saidText = link.saidName else { continue }
            let said = SaidName(ref: saidText)
            guard let saidName = said.name else { continue }
            seen.insert(person.id)
            // The person is on file with the said name, so they would find themselves (rule 4): they are left out.
            let others = try store.personLinks.known().filter { $0.id != person.id }
            let result = PersonGuess.guess(said, people: others, contacts: contacts)
            guard case .contact(let identifier) = result.choice, result.rule == 3 || result.rule == 5,
                  let contact = contacts.first(where: { $0.identifier == identifier }) else { continue }
            let links = try store.people.linkFromReguess(person.id, to: contact, saidName: saidName, in: session)
            changed += links
            if links > 0 { linked.append(person.id) }
        }
        return Reguess(changedLinks: changed, linkedPeople: linked)
    }

    /// What `reguess` did: the `new` links that became `assumed`, and the people it linked to a contact, in link order.
    public struct Reguess: Sendable, Equatable {
        public var changedLinks: Int
        public var linkedPeople: [PersonID]
    }
}
