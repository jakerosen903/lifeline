import Foundation
import GRDB

/// People, their aliases, the "Who's this?" mentions, and places.
/// Name matching ignores case and surrounding whitespace, never spelling.
public struct PeopleRepository: Sendable {
    public enum Error: Swift.Error, Equatable {
        case emptyName
    }

    let db: AppDatabase

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

    /// Every alias of every person who is not the owner and whose entity is not hidden, by the person's entity, in one statement.
    public func allAliases() throws -> [EntityID: [String]] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select person.entity_id as entity_id, alias.text as text
                from alias
                join person on person.id = alias.person_id
                join entity on entity.id = person.entity_id
                where person.is_owner = 0 and entity.hidden_from_timeline = 0
                order by alias.text
                """)
            var out: [EntityID: [String]] = [:]
            for row in rows { out[EntityID(rawValue: row["entity_id"]), default: []].append(row["text"]) }
            return out
        }
    }

    /// The person linked to this contact, if any. The unique index allows at most one.
    public func person(holding identifier: String) throws -> Person? {
        try db.writer.read { try Person.fetchOne($0, sql: Person.selectSQL + "where person.contact_identifier = ?", arguments: [identifier]) }
    }

    /// Every person linked to a contact, by name.
    public func linkedPersons() throws -> [Person] {
        try db.writer.read {
            try Person.fetchAll($0, sql: Person.selectSQL + "where person.contact_identifier is not null order by entity.title collate nocase")
        }
    }

    public func aliases(of person: PersonID) throws -> [Alias] {
        try db.writer.read { try Alias.filter(Column("person_id") == person.rawValue).order(Column("text")).fetchAll($0) }
    }

    /// Each non-owner person's name for a model (`NameForModel`), by entity. A person with none is absent.
    public func namesForModel() throws -> [EntityID: String] {
        try db.writer.read { db in
            var aliases: [String: [Alias]] = [:]
            for alias in try Alias.order(Column.rowID).fetchAll(db) { aliases[alias.personID.rawValue, default: []].append(alias) }
            let people = try Person.fetchAll(db, sql: Person.selectSQL + "where person.is_owner = 0")
            return people.reduce(into: [:]) { names, person in
                names[person.entityID] = NameForModel.of(person, aliasesOldestFirst: aliases[person.id.rawValue] ?? [])
            }
        }
    }

    /// One person's name for a model; nil for a person whose name came from a contact and who has no alias.
    public func nameForModel(of person: PersonID) throws -> String? {
        guard let found = try self.person(id: person) else { return nil }
        return NameForModel.of(found, aliasesOldestFirst: try aliasesOldestFirst(of: person))
    }

    /// The aliases in the order they were saved. The alias table has an implicit rowid, which grows with
    /// each insert and survives the backup (a page copy); the app never runs VACUUM, which could renumber it.
    public func aliasesOldestFirst(of person: PersonID) throws -> [Alias] {
        try db.writer.read { try Alias.filter(Column("person_id") == person.rawValue).order(Column.rowID).fetchAll($0) }
    }

    /// The person whose display name or any alias equals `text`, ignoring case and outer
    /// whitespace. A phrase with a role and a name ("my mom, Marcel") matches on either part.
    /// Never the owner: the owner is the speaker, not someone a story mentions (audit F10).
    /// Only for a name the owner types; no extraction path may call it (it picks one person with no mark).
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
                where person.is_owner = 0 and (lower(trim(entity.title)) = ? or lower(trim(alias.text)) = ?)
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
    public static func relationLabel(aliases: [Alias]) -> String? { relationLabel(texts: aliases.map(\.text)) }

    static func relationLabel(texts: [String]) -> String? {
        texts.first { text in
            let lower = text.lowercased()
            return lower.hasPrefix("my ") || lower.hasPrefix("our ")
        }
    }

    /// Changes the display name and keeps the old spelling as an alias, so a transcript that
    /// repeats the old spelling still links. A name the owner typed makes the person theirs: no
    /// longer a guess a move may remove.
    public func rename(_ person: PersonID, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Error.emptyName }
        try db.writer.write { db in try Self.rename(person, to: name, in: db) }
    }

    /// The one rename of a person, for People and for the person's page (`EntityRepository.rename`).
    /// `name` is already trimmed and not empty.
    static func rename(_ person: PersonID, to name: String, in db: Database) throws {
        guard let old = try String.fetchOne(db, sql: "select title from entity where id = ?", arguments: [person.rawValue]) else { return }
        let oldOrigin = try String.fetchOne(db, sql: "select name_origin from person where id = ?", arguments: [person.rawValue])
        try db.execute(sql: "update entity set title = ? where id = ?", arguments: [name, person.rawValue])
        try db.execute(sql: "update person set created_by_guess = 0, name_origin = ? where id = ?",
                       arguments: [NameOrigin.typed.rawValue, person.rawValue])
        // A name that came from a contact is the contact's, never an alias (PB10): only the owner's words are kept.
        if oldOrigin != NameOrigin.contact.rawValue { try insertAlias(old, person, db) }
        try insertAlias(name, person, db)
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

    /// For a name the person typed or chose themselves: the person it names, and the owner when
    /// it is one of the owner's names. A name the extractor found never comes here or to
    /// `findPerson`: it goes through `PersonGuess` on Keep. Without this, typing your own name
    /// would make a second person with it.
    public func findPersonOrOwner(matching text: String) throws -> Person? {
        if let person = try findPerson(matching: text) { return person }
        guard try ownerNames().isOwner(text) else { return nil }
        return try db.writer.read { try Person.fetchOne($0, sql: Person.selectSQL + "where person.is_owner = 1") }
    }

    /// The owner's typed name and every other name the app holds for them. Empty with no owner.
    public func ownerNames() throws -> OwnerNames {
        try db.writer.read { db in
            guard let owner = try Person.fetchOne(db, sql: Person.selectSQL + "where person.is_owner = 1") else { return OwnerNames(names: []) }
            let aliases = try String.fetchAll(db, sql: "select text from alias where person_id = ?", arguments: [owner.id.rawValue])
            return OwnerNames(names: [owner.displayName] + aliases)
        }
    }

    /// "That's me": the name is one of the owner's from now on. Does nothing with no owner.
    public func addOwnerAlias(_ text: String) throws {
        try db.writer.write { db in
            guard let owner = try Person.fetchOne(db, sql: Person.selectSQL + "where person.is_owner = 1") else { return }
            try Self.insertAlias(text, owner.id, db)
        }
    }

    /// No-op when the person already has this alias (case-insensitive).
    public func addAlias(_ text: String, to person: PersonID) throws {
        try db.writer.write { db in _ = try Self.insertAlias(text, person, db) }
    }

    public func insertMention(_ mention: Mention) throws {
        try db.writer.write { try mention.insert($0) }
    }

    /// Sets the kin or role phrase on a mention that has none (Keep wrote the row before the chip's phrase arrived).
    public func setRelationIfMissing(_ id: MentionID, _ relation: String) throws {
        try db.writer.write { db in
            guard var row = try Mention.fetchOne(db, key: id.rawValue), row.relationText == nil else { return }
            row.relationText = relation
            try row.update(db)
        }
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
    /// A group phrase is not recorded: who "our parents" means depends on the story.
    public func resolve(_ id: MentionID, to person: PersonID) throws {
        try db.writer.write { db in
            guard var mention = try Mention.fetchOne(db, key: id.rawValue) else { return }
            mention.status = .resolved
            mention.personID = person
            try mention.update(db)
            // A phrase for several people ("our parents") is never one person's name.
            if !GroupPhrase.isGroup(mention.text) { try Self.insertAlias(mention.text, person, db) }
            if let relation = mention.relationText, !GroupPhrase.isGroup(relation) { try Self.insertAlias(relation, person, db) }
        }
    }

    /// Reopens a mention marked "not a person" by mistake.
    public func reopen(_ id: MentionID) throws {
        try db.writer.write { db in
            try db.execute(sql: "update mention set status = ?, person_id = null where id = ?",
                           arguments: [MentionStatus.unresolved.rawValue, id.rawValue])
        }
    }

    /// A group phrase answered: the mention is settled and names no one person.
    public func markGroupAnswered(_ id: MentionID) throws {
        try db.writer.write { db in
            try db.execute(sql: "update mention set status = ?, person_id = null where id = ?",
                           arguments: [MentionStatus.resolved.rawValue, id.rawValue])
        }
    }

    /// Takes a name away from a person. No memory changes: the links stay. A later story that
    /// says the name no longer links to this person by it.
    public func removeAlias(_ text: String, from person: PersonID) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from alias where person_id = ? and lower(trim(text)) = ?", arguments: [person.rawValue, Self.normalize(text)])
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

    /// True when the alias is new; false when the person already had it or the text is empty.
    @discardableResult
    static func insertAlias(_ text: String, _ person: PersonID, _ db: Database) throws -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let exists = try Alias.fetchOne(db, sql: "select * from alias where person_id = ? and lower(trim(text)) = ?",
                                        arguments: [person.rawValue, normalize(trimmed)]) != nil
        if !exists { try Alias(personID: person, text: trimmed).insert(db) }
        return !exists
    }

    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
