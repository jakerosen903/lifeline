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
            // The owner is an entity too (M7): "About you" is its details. Its title is the profile's name.
            var owner = try Person.fetchOne(db, sql: Person.selectSQL + "where person.is_owner = 1")
            if owner == nil {
                let fresh = Person(id: .init(), displayName: profile.displayName ?? "", notes: nil, isOwner: true, birthDate: nil, birthDateOrigin: nil)
                try Entity(id: fresh.entityID, type: .person, title: fresh.displayName).insert(db)
                owner = fresh
            }
            guard var owner else { return }
            owner.birthDate = profile.birthDate
            owner.birthDateOrigin = profile.birthDate == nil ? nil : .typed
            try owner.save(db)
            try db.execute(sql: "update entity set title = ? where id = ?", arguments: [profile.displayName ?? "", owner.id.rawValue])
        }
    }

    /// The owner's birthday as a calendar date, from the profile (typed) or the owner row (stated).
    public func ownerBirthDate() throws -> CivilDate? {
        let date = try fetch()?.birthDate ?? owner()?.birthDate
        guard let date else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return CivilDate(year: y, month: m, day: d)
    }

    public func owner() throws -> Person? {
        try db.writer.read { try Person.fetchOne($0, sql: Person.selectSQL + "where person.is_owner = 1") }
    }
}
