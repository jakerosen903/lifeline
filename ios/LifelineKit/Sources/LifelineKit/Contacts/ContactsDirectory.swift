import Foundation

/// What the app may do with the phone's contacts. `restricted` reads as `denied`.
public enum ContactsAccess: String, Sendable { case full, limited, notAsked, denied }

/// One contact: the name fields, the nickname and whether a picture exists. Nothing else is read.
public struct ContactCard: Sendable, Equatable, Identifiable {
    public var identifier: String
    public var fullName: String
    public var givenName: String
    public var familyName: String
    public var nickname: String
    public var hasPicture: Bool
    public var id: String { identifier }

    public init(identifier: String, fullName: String, givenName: String, familyName: String,
                nickname: String, hasPicture: Bool) {
        self.identifier = identifier; self.fullName = fullName; self.givenName = givenName
        self.familyName = familyName; self.nickname = nickname; self.hasPicture = hasPicture
    }

    public var forGuess: PersonGuess.Contact {
        PersonGuess.Contact(identifier: identifier, fullName: fullName, givenName: givenName, nickname: nickname)
    }
}

/// The seam to the system contacts. The app implements it with `Contacts`; tests script it.
public protocol ContactsDirectory: Sendable {
    func access() -> ContactsAccess
    func requestAccess() async -> ContactsAccess
    /// Names only. Under `limited` access, the shared contacts.
    func all() async throws -> [ContactCard]
    /// The unified card for each stored identifier. A missing identifier is absent from the result.
    func cards(identifiers: [String]) async throws -> [ContactCard]
    func picture(identifier: String) async throws -> Data?
}
