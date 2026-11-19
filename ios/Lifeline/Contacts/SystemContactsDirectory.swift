import Contacts
import Foundation
import LifelineKit

/// The phone's contacts, through `CNContactStore`. The only file in the app that imports `Contacts`.
/// It reads the name fields, the nickname and whether a picture exists; a picture's bytes only in
/// `picture(identifier:)`. It requests no phone, email, address, note or any other key.
/// Every read runs in a detached task, off the main thread: a store read blocks until it ends.
/// Each read makes its own store, so the type holds nothing and is `Sendable`; nothing makes a store
/// until a method runs, so a scripted launch, which never makes this type, never touches the system.
struct SystemContactsDirectory: ContactsDirectory {
    /// The notice the system posts when contacts change while the app runs. The app observes it for the check.
    static let didChange = Notification.Name.CNContactStoreDidChange

    /// Name fields only. The formatter's own descriptor names the keys it needs for a full name. Printed from the
    /// macOS 27.2 SDK (2026-11-19): name prefix, given, middle, family, suffix, nickname, the two sorting names, the
    /// display name order, and the organization name with the contact type (a company card is named by its
    /// organization). No phone, email, address, note or date. Check it again on the device (device check).
    private static var nameKeys: [CNKeyDescriptor] {
        [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
         CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor,
         CNContactMiddleNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor,
         CNContactImageDataAvailableKey as CNKeyDescriptor]
    }

    /// The full picture first, the thumbnail when there is no full one. Read for a link or the check only.
    private static var pictureKeys: [CNKeyDescriptor] {
        [CNContactImageDataKey as CNKeyDescriptor, CNContactThumbnailImageDataKey as CNKeyDescriptor]
    }

    func access() -> ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: .full
        case .limited: .limited
        case .notDetermined: .notAsked
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    /// Shows the system prompt the first time; later calls answer at once. The answer is read back from the status,
    /// which tells full from limited; an error reads as whatever the status now says.
    func requestAccess() async -> ContactsAccess {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return access()
    }

    func all() async throws -> [ContactCard] {
        guard canRead else { return [] }
        return try await Task.detached(priority: .utility) {
            let request = CNContactFetchRequest(keysToFetch: Self.nameKeys)
            request.unifyResults = true
            var cards: [ContactCard] = []
            try CNContactStore().enumerateContacts(with: request) { contact, _ in cards.append(Self.card(contact)) }
            return cards
        }.value
    }

    /// The system answers each identifier with its unified card, whose identifier may differ from the one asked for.
    func cards(identifiers: [String]) async throws -> [ContactCard] {
        guard canRead, !identifiers.isEmpty else { return [] }
        return try await Task.detached(priority: .utility) {
            try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: identifiers),
                                                 keysToFetch: Self.nameKeys).map(Self.card)
        }.value
    }

    /// Nil when the contact has no picture or is gone.
    func picture(identifier: String) async throws -> Data? {
        guard canRead else { return nil }
        return try await Task.detached(priority: .utility) {
            let contact: CNContact
            do {
                contact = try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: Self.pictureKeys)
            } catch let error as CNError where error.code == .recordDoesNotExist {
                return nil
            }
            return contact.imageData ?? contact.thumbnailImageData
        }.value
    }

    /// Without access the system answers with an error; the protocol's answer is "nothing", as the scripted one gives.
    private var canRead: Bool {
        switch access() {
        case .full, .limited: true
        case .notAsked, .denied: false
        }
    }

    private static func card(_ contact: CNContact) -> ContactCard {
        ContactCard(identifier: contact.identifier,
                    fullName: CNContactFormatter.string(from: contact, style: .fullName) ?? "",
                    givenName: contact.givenName, familyName: contact.familyName, nickname: contact.nickname,
                    hasPicture: contact.imageDataAvailable)
    }
}
