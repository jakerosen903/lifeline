import Foundation

/// What the owner typed on the "About you" screen. Every field is optional.
/// A saved profile with every field nil still means "the owner has seen the screen".
public struct Profile: Codable, Sendable, Equatable {
    public var displayName: String?
    public var birthDate: Date?
    public var birthPlaceText: String?
    public var freeText: String?
    public var updatedAt: Date

    public init(displayName: String?, birthDate: Date?, birthPlaceText: String?, freeText: String?, updatedAt: Date) {
        self.displayName = displayName
        self.birthDate = birthDate
        self.birthPlaceText = birthPlaceText
        self.freeText = freeText
        self.updatedAt = updatedAt
    }
}

/// Where a birth date came from. `typed` is the About you screen; `stated` is speech.
public enum BirthDateOrigin: String, Codable, Sendable {
    case stated, typed
}

public struct Person: Codable, Sendable, Equatable, Identifiable {
    public var id: PersonID
    public var displayName: String
    public var notes: String?
    public var isOwner: Bool
    public var birthDate: Date?
    public var birthDateOrigin: BirthDateOrigin?
    /// A person is an entity (M7); they share one id.
    public var entityID: EntityID { EntityID(rawValue: id.rawValue) }

    public init(id: PersonID, displayName: String, notes: String?, isOwner: Bool, birthDate: Date?, birthDateOrigin: BirthDateOrigin?) {
        self.id = id
        self.displayName = displayName
        self.notes = notes
        self.isOwner = isOwner
        self.birthDate = birthDate
        self.birthDateOrigin = birthDateOrigin
    }
}
