import Foundation
import GRDB

/// The owner removed the app's copy of a contact's picture from a person's page (I-3). The app must not copy that
/// contact's picture again for that person, or the next check would put it back. The removal is kept, with no new
/// table, as one row of `contact_declined` whose `contact_identifier` is `picture:` and the contact's identifier.
/// No real contact identifier starts with that prefix, and `declinedContacts(of:)` leaves these rows out. Only the
/// functions here read or write the marker. A link to another contact and an unlink forget it; a contact the system
/// merged keeps it under the new identifier.
extension PeopleRepository {
    private static let pictureRemovedPrefix = "picture:"

    private static func pictureRemovedMarker(_ identifier: String) -> String { pictureRemovedPrefix + identifier }

    /// The SQL condition that leaves the markers out of a read of `contact_declined`.
    static let notAPictureRemoval = "contact_identifier not like '\(pictureRemovedPrefix)%'"

    /// Writes the marker when `photo` is the person's copy of their contact's picture. Anything else writes nothing.
    func markPictureRemoved(_ photo: PhotoID, from id: PersonID) throws {
        try db.writer.write { db in
            guard let person = try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ?", arguments: [id.rawValue]),
                  let identifier = person.contactIdentifier, person.contactPhotoID == photo else { return }
            try db.execute(sql: "insert or ignore into contact_declined (person_id, contact_identifier) values (?, ?)",
                           arguments: [id.rawValue, Self.pictureRemovedMarker(identifier)])
        }
    }

    /// True when the owner removed the copy of `identifier`'s picture from this person.
    func pictureWasRemoved(_ id: PersonID, identifier: String) throws -> Bool {
        try db.writer.read { db in
            try Bool.fetchOne(db, sql: "select exists (select 1 from contact_declined where person_id = ? and contact_identifier = ?)",
                              arguments: [id.rawValue, Self.pictureRemovedMarker(identifier)]) ?? false
        }
    }

    /// Forgets every removal for the person: the caller's transaction unlinks them or links another contact.
    static func forgetPictureRemovals(_ id: PersonID, in db: Database) throws {
        try db.execute(sql: "delete from contact_declined where person_id = ? and not (\(notAPictureRemoval))", arguments: [id.rawValue])
    }

    /// The system returns the person's contact under a new identifier: the removal follows it. In the caller's transaction.
    static func movePictureRemoval(_ id: PersonID, from old: String, to new: String, in db: Database) throws {
        try db.execute(sql: "update or ignore contact_declined set contact_identifier = ? where person_id = ? and contact_identifier = ?",
                       arguments: [pictureRemovedMarker(new), id.rawValue, pictureRemovedMarker(old)])
    }
}
