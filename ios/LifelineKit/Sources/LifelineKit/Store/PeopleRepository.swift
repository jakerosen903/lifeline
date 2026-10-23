import Foundation
import GRDB

/// People, their aliases, the "Who's this?" mentions, and places.
/// Name matching ignores case and surrounding whitespace, never spelling.
public struct PeopleRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// Owner first, then by display name.
    public func people() throws -> [Person] {
        try db.writer.read {
            try Person.order(Column("is_owner").desc, Column("display_name").collating(.nocase)).fetchAll($0)
        }
    }

    public func person(id: PersonID) throws -> Person? {
        try db.writer.read { try Person.fetchOne($0, key: id.rawValue) }
    }

    public func aliases(of person: PersonID) throws -> [Alias] {
        try db.writer.read { try Alias.filter(Column("person_id") == person.rawValue).order(Column("text")).fetchAll($0) }
    }

    /// The person whose display name or any alias equals `text`, ignoring case and outer whitespace.
    public func findPerson(matching text: String) throws -> Person? {
        let needle = Self.normalize(text)
        guard !needle.isEmpty else { return nil }
        return try db.writer.read { db in
            try Person.fetchOne(db, sql: """
                select person.* from person
                left join alias on alias.person_id = person.id
                where lower(trim(person.display_name)) = ? or lower(trim(alias.text)) = ?
                limit 1
                """, arguments: [needle, needle])
        }
    }

    /// Inserts a person and the alias equal to their name.
    public func insertPerson(displayName: String) throws -> Person {
        let person = Person(id: .init(), displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil)
        try db.writer.write { db in
            try person.insert(db)
            try Self.insertAlias(person.displayName, person.id, db)
        }
        return person
    }

    /// No-op when the person already has this alias (case-insensitive).
    public func addAlias(_ text: String, to person: PersonID) throws {
        try db.writer.write { db in try Self.insertAlias(text, person, db) }
    }

    public func insertMention(_ mention: Mention) throws {
        try db.writer.write { try mention.insert($0) }
    }

    public func mention(id: MentionID) throws -> Mention? {
        try db.writer.read { try Mention.fetchOne($0, key: id.rawValue) }
    }

    public func mentions(status: MentionStatus) throws -> [Mention] {
        try db.writer.read { try Mention.filter(Column("status") == status.rawValue).fetchAll($0) }
    }

    public func mentions(in segment: SegmentID) throws -> [Mention] {
        try db.writer.read { try Mention.filter(Column("segment_id") == segment.rawValue).fetchAll($0) }
    }

    /// Marks the mention resolved to `person` and records its text as an alias.
    public func resolve(_ id: MentionID, to person: PersonID) throws {
        try db.writer.write { db in
            guard var mention = try Mention.fetchOne(db, key: id.rawValue) else { return }
            mention.status = .resolved
            mention.personID = person
            try mention.update(db)
            try Self.insertAlias(mention.text, person, db)
        }
    }

    public func markNotAPerson(_ id: MentionID) throws {
        try db.writer.write { db in
            try db.execute(sql: "update mention set status = ?, person_id = null where id = ?",
                           arguments: [MentionStatus.notAPerson.rawValue, id.rawValue])
        }
    }

    /// Reuses a place with the same name, ignoring case.
    public func insertPlace(nameText: String) throws -> Place {
        let needle = Self.normalize(nameText)
        return try db.writer.write { db in
            if let existing = try Place.fetchOne(db, sql: "select * from place where lower(trim(name_text)) = ?", arguments: [needle]) {
                return existing
            }
            let place = Place(id: .init(), nameText: nameText.trimmingCharacters(in: .whitespacesAndNewlines), lat: nil, lon: nil)
            try place.insert(db)
            return place
        }
    }

    private static func insertAlias(_ text: String, _ person: PersonID, _ db: Database) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = try Alias.fetchOne(db, sql: "select * from alias where person_id = ? and lower(trim(text)) = ?",
                                        arguments: [person.rawValue, normalize(trimmed)]) != nil
        if !exists { try Alias(personID: person, text: trimmed).insert(db) }
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
