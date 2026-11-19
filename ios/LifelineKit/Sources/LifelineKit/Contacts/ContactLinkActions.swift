import Foundation

/// A person and a contact: link, unlink, and the copy of the contact's picture (spec, "Linking and
/// unlinking" and "The picture"). One contact belongs to one person.
public struct ContactLinkActions: Sendable {
    public enum Error: Swift.Error, Equatable {
        /// Another person holds the contact; `name` is that person's display name.
        case heldByAnother(PersonID, name: String)
        case notFound
    }

    private let store: ExtractionStore
    private let photos: PhotoLibrary
    private let directory: any ContactsDirectory
    /// Where `copyPicture` makes its fresh folder for the picture's bytes. A test passes its own.
    private let scratch: URL

    public init(store: ExtractionStore, photos: PhotoLibrary, directory: any ContactsDirectory) {
        self.init(store: store, photos: photos, directory: directory, scratch: FileManager.default.temporaryDirectory)
    }

    init(store: ExtractionStore, photos: PhotoLibrary, directory: any ContactsDirectory, scratch: URL) {
        self.store = store; self.photos = photos; self.directory = directory; self.scratch = scratch
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

    /// Copies the contact's picture onto the person's page, after their other photos. Safe to call twice
    /// and after a kill: nothing happens when the person has a copy already, has no contact, or the contact
    /// has no picture. A picture with the bytes of a stored photo links that photo and is not recorded as
    /// the copy, so the app never later replaces or removes the owner's photo.
    public func copyPicture(for id: PersonID) async throws {
        guard let person = try store.people.person(id: id), let identifier = person.contactIdentifier, person.contactPhotoID == nil,
              let data = try await directory.picture(identifier: identifier), !data.isEmpty else { return }
        let folder = scratch.appending(path: "contact-picture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "picture")
        try data.write(to: file)
        let subject = PhotoSubject.entity(person.entityID)
        let added = try await photos.addNotingNew(fileAt: file, assetLocalID: nil, to: subject)
        guard added.isNew else { return }
        // The contact changed, or another copy was recorded, while this one was made: the app keeps only what it records.
        if try !store.people.recordContactPhoto(added.photo.id, for: id, identifier: identifier) {
            try await photos.remove(added.photo.id, from: subject)
        }
    }
}
