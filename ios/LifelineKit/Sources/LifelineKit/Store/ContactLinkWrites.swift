import Foundation
import GRDB

/// The writes behind `ContactLinkActions`. Each runs in one transaction and reads the person inside it,
/// so a kill leaves the old state or the new one. The rules are in `docs/specs/2026-11-18-people-contacts.md`,
/// "Linking and unlinking" and "The picture".
extension PeopleRepository {
    /// Sets the contact's identifier, name and state. Refuses, before the unique index can throw, when
    /// another person holds the contact. A link to another contact first takes off the app's copy of the
    /// old contact's picture: only the photo in `contact_photo_id`, never a photo the owner added. Returns
    /// that photo when its row was deleted (no other page held it), so the caller deletes the file.
    /// `clearingGuess` is true for the owner's link and false for the app's own (PB3).
    func linkContact(_ id: PersonID, to card: ContactCard, clearingGuess: Bool) throws -> Photo? {
        try db.writer.write { db in
            guard let person = try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ?", arguments: [id.rawValue]) else {
                throw ContactLinkActions.Error.notFound
            }
            if let holder = try Person.fetchOne(db, sql: Person.selectSQL + "where person.contact_identifier = ? and person.id <> ?",
                                                arguments: [card.identifier, id.rawValue]) {
                throw ContactLinkActions.Error.heldByAnother(holder.id, name: holder.displayName)
            }
            var gone: Photo?
            if person.contactIdentifier != card.identifier, let copy = person.contactPhotoID {
                try db.execute(sql: "update person set contact_photo_id = null where id = ?", arguments: [id.rawValue])
                _ = try PhotoRepository.removeLink(copy, from: .entity(person.entityID), in: db)
                gone = try PhotoRepository.deleteIfHomeless(copy, in: db)
            }
            // Another contact is another picture: a removal of the old copy is forgotten (I-3).
            if person.contactIdentifier != card.identifier { try Self.forgetPictureRemovals(id, in: db) }
            // The name and `name_origin` stay: a person on file keeps their name (spec, "The person's name").
            try db.execute(sql: "update person set contact_identifier = ?, contact_name = ?, contact_state = ? where id = ?",
                           arguments: [card.identifier, card.keptName, Person.contactLinked, id.rawValue])
            if clearingGuess {
                try db.execute(sql: "update person set created_by_guess = 0 where id = ?", arguments: [id.rawValue])
            }
            return gone
        }
    }

    /// Clears the identifier, the kept name, the state and `contact_photo_id`. The copied picture stays as an
    /// ordinary photo of the person; the person, moments and aliases are not touched. The owner acted, so the
    /// person is no longer a guess a move may remove (PB19). No contact: nothing changes.
    func unlinkContact(_ id: PersonID) throws {
        try db.writer.write { db in
            guard try Person.exists(db, key: id.rawValue) else { throw ContactLinkActions.Error.notFound }
            try db.execute(sql: """
                update person set contact_identifier = null, contact_name = null, contact_state = null, contact_photo_id = null,
                    created_by_guess = 0
                where id = ? and (contact_identifier is not null or contact_photo_id is not null)
                """, arguments: [id.rawValue])
            try Self.forgetPictureRemovals(id, in: db)   // a fresh link later copies the picture again (I-3)
        }
    }

    /// Thrown inside the copy's transaction when the person no longer holds the contact, or has a copy now,
    /// so the photo row and its link roll back with it.
    struct ContactChangedDuringCopy: Swift.Error {}

    /// Records `photo` as the app's copy of the contact's picture, only while the person is still linked to
    /// `identifier` and has no copy. Runs in the transaction that inserts the photo (`PhotoLibrary.addRecordingNew`).
    static func recordContactPhoto(_ photo: PhotoID, for id: PersonID, identifier: String, in db: Database) throws {
        try db.execute(sql: "update person set contact_photo_id = ? where id = ? and contact_identifier = ? and contact_photo_id is null",
                       arguments: [photo.rawValue, id.rawValue, identifier])
        if db.changesCount == 0 { throw ContactChangedDuringCopy() }
    }
}

// MARK: - The check, the suggestion and the look again after access (Task 4)

/// What the check did for one linked person.
enum ContactFollow: Equatable {
    /// The person follows the card: identifier, kept name, state, and a name that came from the contact.
    case followed
    /// The card's identifier is another person's, so this person's contact is missing.
    case missing
    /// The person no longer holds the identifier the check read: the owner acted meanwhile. Nothing was written.
    case changed
}

extension PeopleRepository {
    /// The person follows `card`, which the system returned for `stored`: the identifier the system returns now
    /// (a unified card, or a re-link by name), the contact's name, and the state "linked". The display name follows
    /// only when it came from the contact (`name_origin` contact; a rename sets `typed`). The contact's name is
    /// never saved as an alias (PB10). One transaction, read inside it.
    func followContact(_ id: PersonID, from stored: String, to card: ContactCard) throws -> ContactFollow {
        try db.writer.write { db in
            guard let person = try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ? and person.contact_identifier = ?",
                                                   arguments: [id.rawValue, stored]) else { return .changed }
            if card.identifier != stored,
               try Bool.fetchOne(db, sql: "select exists (select 1 from person where contact_identifier = ? and id <> ?)",
                                 arguments: [card.identifier, id.rawValue]) == true {
                try Self.markContactMissing(id, from: stored, in: db)
                return .missing
            }
            let name = card.keptName
            // Nothing changed: nothing is written, so a check of an unchanged contact is free at every launch.
            if card.identifier != stored || person.contactName != name || person.contactState != Person.contactLinked {
                try db.execute(sql: "update person set contact_identifier = ?, contact_name = ?, contact_state = ? where id = ?",
                               arguments: [card.identifier, name, Person.contactLinked, id.rawValue])
            }
            if card.identifier != stored { try Self.movePictureRemoval(id, from: stored, to: card.identifier, in: db) }
            // A contact with no name keeps the person's name: a page never loses its title.
            if person.nameOrigin == .contact, !name.isEmpty, name != person.displayName {
                try db.execute(sql: "update entity set title = ? where id = ?", arguments: [name, person.entityID.rawValue])
            }
            return .followed
        }
    }

    /// The state "missing" and nothing else: the person keeps the identifier, the kept name and the picture.
    func markContactMissing(_ id: PersonID, from stored: String) throws {
        try db.writer.write { try Self.markContactMissing(id, from: stored, in: $0) }
    }

    private static func markContactMissing(_ id: PersonID, from stored: String, in db: Database) throws {
        try db.execute(sql: "update person set contact_state = ? where id = ? and contact_identifier = ? and contact_state is not ?",
                       arguments: [Person.contactMissing, id.rawValue, stored, Person.contactMissing])
    }

    /// The contact's new picture replaces the app's copy, in the transaction that inserts the new photo and its
    /// link (`PhotoLibrary.addRecordingNew`): the new photo becomes first, `contact_photo_id` points at it, and the
    /// old copy's link to the person goes, its row too when no other page holds it. Returns that row, so the caller
    /// deletes the file after the commit. Throws `ContactChangedDuringCopy`, and so rolls the new photo back, unless
    /// the person still holds `identifier`, `old` is still the copy, and it is still the person's first photo.
    static func replaceContactPhoto(_ old: PhotoID, with new: PhotoID, for id: PersonID, identifier: String, in db: Database) throws -> Photo? {
        let page = PhotoSubject.entity(EntityID(rawValue: id.rawValue))
        let still = try Bool.fetchOne(db, sql: """
            select exists (select 1 from person where id = ? and contact_identifier = ? and contact_photo_id = ?)
            """, arguments: [id.rawValue, identifier, old.rawValue]) ?? false
        guard still, try PhotoRepository.firstPhoto(of: page, in: db) == old else { throw ContactChangedDuringCopy() }
        try db.execute(sql: "update person set contact_photo_id = ? where id = ?", arguments: [new.rawValue, id.rawValue])
        try PhotoRepository.setCover(new, of: page, in: db)
        _ = try PhotoRepository.removeLink(old, from: page, in: db)
        return try PhotoRepository.deleteIfHomeless(old, in: db)
    }

    /// "No, someone else": the contact is not offered for this person again. A second decline writes nothing.
    func declineContact(_ identifier: String, for id: PersonID) throws {
        try db.writer.write { db in
            guard try Person.exists(db, key: id.rawValue) else { throw ContactLinkActions.Error.notFound }
            try db.execute(sql: "insert or ignore into contact_declined (person_id, contact_identifier) values (?, ?)",
                           arguments: [id.rawValue, identifier])
        }
    }

    func declinedContacts(of id: PersonID) throws -> Set<String> {
        try db.writer.read { db in
            Set(try String.fetchAll(db, sql: "select contact_identifier from contact_declined where person_id = ? and \(Self.notAPictureRemoval)",
                                    arguments: [id.rawValue]))
        }
    }

    /// The look again after access (plan decision 7) for one person the app made: the app's link to `contact`
    /// (`created_by_guess` stays, PB3), the contact's full name as the person's name with `name_origin` contact,
    /// and each of the person's `new` mention links in `session` becomes `assumed`. The said name, and the name the
    /// person was made with, stay as aliases: they are the owner's words and the model's name for them (PB10).
    /// One transaction. Returns the links changed: 0 when the person is no longer the app's untouched guess with
    /// no contact, another person holds the contact, or the owner declined it for this person.
    func linkFromReguess(_ id: PersonID, to contact: PersonGuess.Contact, saidName: String, in session: SessionID) throws -> Int {
        let name = contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return 0 }
        return try db.writer.write { db in
            guard let person = try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ?", arguments: [id.rawValue]),
                  !person.isOwner, person.createdByGuess, person.nameOrigin == .said, person.contactIdentifier == nil,
                  try Bool.fetchOne(db, sql: "select exists (select 1 from person where contact_identifier = ?)",
                                    arguments: [contact.identifier]) == false,
                  // "No, someone else" is kept (PB35).
                  try Bool.fetchOne(db, sql: "select exists (select 1 from contact_declined where person_id = ? and contact_identifier = ?)",
                                    arguments: [id.rawValue, contact.identifier]) == false else { return 0 }
            try Self.insertAlias(person.displayName, id, db)
            try Self.insertAlias(saidName, id, db)
            try db.execute(sql: "update entity set title = ? where id = ?", arguments: [name, person.entityID.rawValue])
            try db.execute(sql: """
                update person set name_origin = ?, contact_identifier = ?, contact_name = ?, contact_state = ? where id = ?
                """, arguments: [NameOrigin.contact.rawValue, contact.identifier, name, Person.contactLinked, id.rawValue])
            try db.execute(sql: """
                update moment_entity set origin = ?
                where entity_id = ? and relation = 'mention' and origin = ? and memory_id in (
                    select ms.memory_id from memory_span ms join segment on segment.id = ms.segment_id
                    where ms."order" = 0 and segment.session_id = ?)
                """, arguments: [LinkOrigin.assumed.rawValue, person.entityID.rawValue, LinkOrigin.new.rawValue, session.rawValue])
            return db.changesCount
        }
    }
}

extension ContactCard {
    /// The contact's full name as the app keeps it in `contact_name`: trimmed, as Keep keeps it.
    public var keptName: String { fullName.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension PersonLinkRepository {
    /// The session's mention links with origin `new`, oldest memory first.
    func newMentionLinks(in session: SessionID) throws -> [PersonLink] {
        try db.writer.read { db in
            try Self.fetch(where: "me.relation = 'mention' and me.origin = ? and \(Self.sessionSQL) = ?",
                           arguments: [LinkOrigin.new.rawValue, session.rawValue], order: "memory.created_at, me.memory_id", in: db)
        }
    }
}
