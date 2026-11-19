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
            // The name and `name_origin` stay: a person on file keeps their name (spec, "The person's name").
            try db.execute(sql: "update person set contact_identifier = ?, contact_name = ?, contact_state = ? where id = ?",
                           arguments: [card.identifier, card.fullName, Person.contactLinked, id.rawValue])
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
