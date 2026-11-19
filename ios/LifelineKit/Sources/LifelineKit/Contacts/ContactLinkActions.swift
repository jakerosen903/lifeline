import Foundation
import GRDB

/// A person and a contact: link, unlink, and the copy of the contact's picture (spec, "Linking and
/// unlinking" and "The picture"). One contact belongs to one person.
public struct ContactLinkActions: Sendable {
    public enum Error: Swift.Error, Equatable {
        /// Another person holds the contact; `name` is that person's display name.
        case heldByAnother(PersonID, name: String)
        case notFound
    }

    // Internal, not private: the check (`ContactCheck.swift`) is an extension in its own file.
    let store: ExtractionStore
    let photos: PhotoLibrary
    let directory: any ContactsDirectory
    /// Where a picture's bytes are written, each in a fresh folder, before the store reads them. A test passes its own.
    let scratch: URL
    /// Runs in the copy's transaction after the photo row and link, before the record. A test throws here.
    private let beforeRecord: @Sendable () throws -> Void

    public init(store: ExtractionStore, photos: PhotoLibrary, directory: any ContactsDirectory) {
        self.init(store: store, photos: photos, directory: directory, scratch: FileManager.default.temporaryDirectory)
    }

    init(store: ExtractionStore, photos: PhotoLibrary, directory: any ContactsDirectory, scratch: URL,
         beforeRecord: @escaping @Sendable () throws -> Void = {}) {
        self.store = store; self.photos = photos; self.directory = directory; self.scratch = scratch; self.beforeRecord = beforeRecord
    }

    /// The owner links the person to `card`, then the picture is copied. The person keeps their name and
    /// `name_origin`; the owner acted, so they are no longer a guess (PB3). A link to a second contact
    /// replaces the first and its copied picture.
    public func link(_ person: PersonID, to card: ContactCard) async throws {
        try await link(person, to: card, clearingGuess: true)
    }

    /// The link, for the app's own action too: the app's link passes `clearingGuess: false` (PB3).
    /// The link is made once the fields are written. A picture that cannot be read or stored is not
    /// the link's failure: `copyPicture` may run again later (PB16).
    func link(_ person: PersonID, to card: ContactCard, clearingGuess: Bool) async throws {
        if let gone = try store.people.linkContact(person, to: card, clearingGuess: clearingGuess) {
            await photos.removeFile(of: gone)
        }
        try? await copyPicture(for: person)
    }

    /// Clears the identifier, the kept name, the state and `contact_photo_id`. The picture stays as an
    /// ordinary photo; the person, their moments and their names stay.
    public func unlink(_ person: PersonID) throws {
        try store.people.unlinkContact(person)
    }

    /// The owner is removing `photo` from the person's page. When it is the app's copy of the contact's picture, the
    /// removal is kept, so no later check or copy puts it back (I-3). Call it before the photo is removed: once the
    /// row is gone, `contact_photo_id` is null and the copy can no longer be told from the owner's photo.
    public func pictureRemoved(_ photo: PhotoID, from person: PersonID) throws {
        try store.people.markPictureRemoved(photo, from: person)
    }

    /// Copies the contact's picture onto the person's page, after their other photos. Safe to call twice
    /// and after a kill: nothing happens when the person has a copy already, has no contact, the owner removed
    /// the copy of this contact's picture (I-3), or the contact has no picture. A picture with the bytes of a stored photo links that photo and is not recorded as
    /// the copy, so the app never later replaces or removes the owner's photo.
    public func copyPicture(for id: PersonID) async throws {
        guard let person = try store.people.person(id: id), let identifier = person.contactIdentifier, person.contactPhotoID == nil,
              try !store.people.pictureWasRemoved(id, identifier: identifier),
              let data = try await directory.picture(identifier: identifier), !data.isEmpty else { return }
        let file = try pictureFile(data)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        // The row, its link and `contact_photo_id` are one transaction, so a kill never leaves the copy looking like
        // the owner's photo. A contact that changed during the copy rolls the photo back: the app keeps only what it records.
        let beforeRecord = self.beforeRecord
        do {
            _ = try await photos.addRecordingNew(fileAt: file, to: .entity(person.entityID)) { db, photo in
                try beforeRecord()
                try PeopleRepository.recordContactPhoto(photo, for: id, identifier: identifier, in: db)
            }
        } catch is PeopleRepository.ContactChangedDuringCopy {
            return
        }
    }

    /// After Keep or "Same story": the contact's picture for each person `memory` names who has a contact and no copy
    /// yet, such as a person Keep just made from a contact (I-2). Returns the people who got a copy. A picture that
    /// cannot be read or stored is skipped; the next check copies it (PB16).
    @discardableResult
    public func copyMissingPictures(of memory: MemoryID) async -> [PersonID] {
        let people = ((try? store.personLinks.links(of: memory)) ?? []).map(\.person)
        var copied: [PersonID] = []
        for person in people where person.contactIdentifier != nil && person.contactPhotoID == nil && !copied.contains(person.id) {
            try? await copyPicture(for: person.id)
            if (try? store.people.person(id: person.id))?.contactPhotoID != nil { copied.append(person.id) }
        }
        return copied
    }

    /// Writes a picture's bytes to a fresh folder under `scratch`, for the store to read. The caller removes the folder.
    func pictureFile(_ data: Data) throws -> URL {
        let folder = scratch.appending(path: "contact-picture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "picture")
        do { try data.write(to: file) } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return file
    }
}
