import Foundation
import GRDB

/// The owner's profile and its mirror on the owner's `person` row.
public struct ProfileRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// nil until the owner has seen the About you screen (Skip saves an empty profile).
    public func fetch() throws -> Profile? {
        try db.writer.read { try ProfileRow.fetchOne($0, key: ProfileRow.singletonID)?.profile }
    }

    /// Upserts the profile and the single owner person in one transaction.
    public func save(_ profile: Profile) throws {
        try db.writer.write { db in
            try ProfileRow(profile).save(db)
            var owner = try Person.filter(Column("is_owner") == true).fetchOne(db)
                ?? Person(id: .init(), displayName: "", notes: nil, isOwner: true, birthDate: nil, birthDateOrigin: nil)
            owner.displayName = profile.displayName ?? ""
            owner.birthDate = profile.birthDate
            owner.birthDateOrigin = profile.birthDate == nil ? nil : .typed
            try owner.save(db)
        }
    }

    public func owner() throws -> Person? {
        try db.writer.read { try Person.filter(Column("is_owner") == true).fetchOne($0) }
    }
}
