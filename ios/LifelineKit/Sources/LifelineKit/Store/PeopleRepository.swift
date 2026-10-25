import Foundation
import GRDB

/// People, their aliases, the "Who's this?" mentions, and places.
/// Name matching ignores case and surrounding whitespace, never spelling.
public struct PeopleRepository: Sendable {
    public enum Error: Swift.Error, Equatable {
        case emptyName
    }

    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// Owner first, then by display name.
    public func people() throws -> [Person] {
        try db.writer.read {
            try Person.fetchAll($0, sql: Person.selectSQL + "order by person.is_owner desc, entity.title collate nocase")
        }
    }

    /// Everyone but the owner, the most recently linked to a kept memory first, then by name.
    /// People never linked come last. Feeds the packet's relevance order (M5).
    public func peopleByRecentLink() throws -> [Person] {
        try db.writer.read { db in
            try Person.fetchAll(db, sql: Person.selectSQL + """
                left join (select me.entity_id, max(memory.created_at) as last_linked from moment_entity me
                           join memory on memory.id = me.memory_id group by me.entity_id) links
                  on links.entity_id = person.entity_id
                where person.is_owner = 0
                order by links.last_linked is null, links.last_linked desc, entity.title collate nocase
                """)
        }
    }

    public func person(id: PersonID) throws -> Person? {
        try db.writer.read { try Person.fetchOne($0, sql: Person.selectSQL + "where person.id = ?", arguments: [id.rawValue]) }
    }

    public func aliases(of person: PersonID) throws -> [Alias] {
        try db.writer.read { try Alias.filter(Column("person_id") == person.rawValue).order(Column("text")).fetchAll($0) }
    }

    /// The person whose display name or any alias equals `text`, ignoring case and outer
    /// whitespace. A phrase with a role and a name ("my mom, Marcel") matches on either part.
    public func findPerson(matching text: String) throws -> Person? {
        for part in Self.parts(of: text) {
            if let person = try findPerson(exactly: part) { return person }
        }
        return nil
    }

    private func findPerson(exactly text: String) throws -> Person? {
        let needle = Self.normalize(text)
        guard !needle.isEmpty else { return nil }
        return try db.writer.read { db in
            try Person.fetchOne(db, sql: Person.selectSQL + """
                left join alias on alias.person_id = person.id
                where lower(trim(entity.title)) = ? or lower(trim(alias.text)) = ?
                limit 1
                """, arguments: [needle, needle])
        }
    }

    /// "my mom, Marcel" -> ["my mom, Marcel", "my mom", "Marcel"]. The whole phrase first.
    public static func parts(of text: String) -> [String] {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let split = whole.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return split.count > 1 ? [whole] + split : [whole]
    }

    /// The alias that reads as a relation to the owner ("my mom", "our dog"), if any.
    public static func relationLabel(aliases: [Alias]) -> String? {
        aliases.map(\.text).first { text in
            let lower = text.lowercased()
            return lower.hasPrefix("my ") || lower.hasPrefix("our ")
        }
    }

    /// Changes the display name and keeps the old spelling as an alias, so a transcript that
    /// repeats the old spelling still links.
    public func rename(_ person: PersonID, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Error.emptyName }
        try db.writer.write { db in
            guard let old = try String.fetchOne(db, sql: "select title from entity where id = ?", arguments: [person.rawValue]) else { return }
            try db.execute(sql: "update entity set title = ? where id = ?", arguments: [name, person.rawValue])
            try Self.insertAlias(old, person, db)
            try Self.insertAlias(name, person, db)
        }
    }

    /// Inserts a person and the alias equal to their name.
    public func insertPerson(displayName: String) throws -> Person {
        let person = Person(id: .init(), displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil)
        try db.writer.write { db in
            try person.insertWithEntity(db)
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

    /// Marks the mention resolved to `person` and records its text, and its relation phrase, as aliases.
    public func resolve(_ id: MentionID, to person: PersonID) throws {
        try db.writer.write { db in
            guard var mention = try Mention.fetchOne(db, key: id.rawValue) else { return }
            mention.status = .resolved
            mention.personID = person
            try mention.update(db)
            try Self.insertAlias(mention.text, person, db)
            if let relation = mention.relationText { try Self.insertAlias(relation, person, db) }
        }
    }

    /// Reopens a mention marked "not a person" by mistake.
    public func reopen(_ id: MentionID) throws {
        try db.writer.write { db in
            try db.execute(sql: "update mention set status = ?, person_id = null where id = ?",
                           arguments: [MentionStatus.unresolved.rawValue, id.rawValue])
        }
    }

    public func markNotAPerson(_ id: MentionID) throws {
        try db.writer.write { db in
            try db.execute(sql: "update mention set status = ?, person_id = null where id = ?",
                           arguments: [MentionStatus.notAPerson.rawValue, id.rawValue])
        }
    }

    /// Reuses a place with the same name, ignoring case. A place is an entity (M7).
    public func insertPlace(nameText: String) throws -> Place {
        Place(try EntityRepository(db).insert(type: .place, title: nameText))
    }

    private static func insertAlias(_ text: String, _ person: PersonID, _ db: Database) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = try Alias.fetchOne(db, sql: "select * from alias where person_id = ? and lower(trim(text)) = ?",
                                        arguments: [person.rawValue, normalize(trimmed)]) != nil
        if !exists { try Alias(personID: person, text: trimmed).insert(db) }
    }

    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
