import Foundation
import GRDB

/// The owner's answer for one said name on one waiting card (`candidate_person_choice`).
/// `choice` is nil when the answer is "not a person".
public struct PersonChoice: Sendable, Equatable {
    public var saidKey: String
    public var choice: PersonGuess.Choice?
    public var notAPerson: Bool
    public init(saidKey: String, choice: PersonGuess.Choice?, notAPerson: Bool) {
        self.saidKey = saidKey; self.choice = choice; self.notAPerson = notAPerson
    }
}

/// Reads of person links for the guess on Keep: who is on file, and what the owner already chose.
public struct PersonLinkRepository: Sendable {
    let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// Every person but the owner, with their aliases and the latest `created_at` of a memory
    /// linked to them (nil when never linked). The owner is never a candidate for a said name.
    public func known() throws -> [PersonGuess.Known] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select person.id, entity.title, person.contact_identifier,
                       (select max(memory.created_at) from moment_entity me join memory on memory.id = me.memory_id
                        where me.entity_id = person.entity_id) as last_linked
                from person join entity on entity.id = person.entity_id
                where person.is_owner = 0
                order by entity.title collate nocase, person.id
                """)
            var aliases: [String: [String]] = [:]
            for row in try Row.fetchAll(db, sql: "select person_id, text from alias order by text") {
                aliases[row["person_id"], default: []].append(row["text"])
            }
            return rows.map { row in
                let id: String = row["id"]
                return PersonGuess.Known(id: PersonID(rawValue: id), name: row["title"], aliases: aliases[id] ?? [],
                                         lastLinked: row["last_linked"], contactIdentifier: row["contact_identifier"])
            }
        }
    }

    /// The owner's stored answers for a waiting card. A row whose choice the app does not know,
    /// or a `person`/`contact` row missing its target, is skipped: the guess decides instead.
    public func choices(for candidate: CandidateID) throws -> [PersonChoice] {
        try db.writer.read { db in
            try Row.fetchAll(db, sql: "select said_name, choice, person_id, contact_identifier from candidate_person_choice where candidate_id = ?",
                             arguments: [candidate.rawValue])
                .compactMap { row -> PersonChoice? in
                    let key = SaidName.key(row["said_name"] as String)
                    switch row["choice"] as String {
                    case "person":
                        return (row["person_id"] as String?).map { PersonChoice(saidKey: key, choice: .person(PersonID(rawValue: $0)), notAPerson: false) }
                    case "contact":
                        return (row["contact_identifier"] as String?).map { PersonChoice(saidKey: key, choice: .contact($0), notAPerson: false) }
                    case "new": return PersonChoice(saidKey: key, choice: .newPerson, notAPerson: false)
                    case "not_a_person": return PersonChoice(saidKey: key, choice: nil, notAPerson: true)
                    default: return nil
                    }
                }
        }
    }

    // MARK: - Reads for the views

    /// The memory's links to people, the owner included when linked, by person name. Mentions only.
    public func links(of memory: MemoryID) throws -> [PersonLink] {
        try fetch(where: "me.memory_id = ? and me.relation = 'mention'", arguments: [memory.rawValue],
                  order: "entity.title collate nocase, person.id")
    }

    /// Every link to a person, in both relations, newest memory first.
    public func links(to person: PersonID) throws -> [PersonLink] {
        try fetch(where: "person.id = ?", arguments: [person.rawValue], order: "memory.created_at desc, me.memory_id, me.relation")
    }

    /// The links one answer can change together: the same person and relation in the same session,
    /// said with the same name (`SaidName.key`). A link with no said name is a group of only itself.
    /// Includes `link`.
    public func group(of link: PersonLink) throws -> [PersonLink] {
        try db.writer.read { try Self.group(of: link, in: $0) }
    }

    static func group(of link: PersonLink, in db: Database) throws -> [PersonLink] {
        let key = SaidName.key(link.saidName ?? "")
        guard !key.isEmpty else { return [link] }
        guard let session = try session(of: link.memoryID, in: db) else { return [link] }
        let sameSession = try fetch(where: "person.id = ? and me.relation = ? and \(sessionSQL) = ?",
                                    arguments: [link.person.id.rawValue, link.relation.rawValue, session],
                                    order: "memory.created_at, me.memory_id", in: db)
        return sameSession.filter { $0.saidName.map(SaidName.key) == key }
    }

    /// How many guesses the session's memories hold: assumed mentions, one per memory and person.
    public func guessCount(in session: SessionID) throws -> Int {
        try db.writer.read { db in
            try Int.fetchOne(db, sql: """
                select count(*) from moment_entity me
                join person on person.entity_id = me.entity_id
                where me.relation = 'mention' and me.origin = 'assumed' and \(Self.sessionSQL) = ?
                """, arguments: [session.rawValue]) ?? 0
        }
    }

    // MARK: - Shared with the writes

    /// The session of the segment of a memory's first span (order 0). `me` is the link's table.
    static let sessionSQL = """
        (select segment.session_id from memory_span ms join segment on segment.id = ms.segment_id
         where ms.memory_id = me.memory_id and ms."order" = 0)
        """

    /// The session of a person's first link: the oldest linked memory's first span. `entity` is an SQL
    /// expression for the person's entity id.
    static func firstSessionSQL(entity: String) -> String {
        """
        (select segment.session_id from moment_entity first_me
         join memory first_memory on first_memory.id = first_me.memory_id
         join memory_span ms on ms.memory_id = first_memory.id and ms."order" = 0
         join segment on segment.id = ms.segment_id
         where first_me.entity_id = \(entity) order by first_memory.created_at, first_memory.id limit 1)
        """
    }

    /// The recording of a person's first link, or nil when they have none.
    public func firstSession(of person: PersonID) throws -> SessionID? {
        try db.writer.read { db in
            try String.fetchOne(db, sql: "select \(Self.firstSessionSQL(entity: "?"))", arguments: [person.rawValue]).map(SessionID.init(rawValue:))
        }
    }

    static func session(of memory: MemoryID, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: """
            select segment.session_id from memory_span ms join segment on segment.id = ms.segment_id
            where ms.memory_id = ? and ms."order" = 0
            """, arguments: [memory.rawValue])
    }

    /// Links to people (never to a place or a thing), each with its person read in full.
    private func fetch(where clause: String, arguments: StatementArguments, order: String) throws -> [PersonLink] {
        try db.writer.read { try Self.fetch(where: clause, arguments: arguments, order: order, in: $0) }
    }

    static func fetch(where clause: String, arguments: StatementArguments, order: String, in db: Database) throws -> [PersonLink] {
        let rows = try Row.fetchAll(db, sql: """
            select me.memory_id, me.relation, me.role_text, me.origin, person.id as person_id,
                   \(sessionSQL) as session_id, \(firstSessionSQL(entity: "me.entity_id")) as first_session_id
            from moment_entity me
            join person on person.entity_id = me.entity_id
            join entity on entity.id = person.entity_id
            join memory on memory.id = me.memory_id
            where \(clause) order by \(order)
            """, arguments: arguments)
        var people: [String: Person] = [:]
        return try rows.compactMap { row -> PersonLink? in
            let personID: String = row["person_id"]
            if people[personID] == nil {
                people[personID] = try Person.fetchOne(db, sql: Person.selectSQL + " where person.id = ?", arguments: [personID])
            }
            guard let person = people[personID], let relation = EntityRelation(rawValue: row["relation"]) else { return nil }
            // A link with no span to read a recording from counts as the first recording.
            let session: String? = row["session_id"], first: String? = row["first_session_id"]
            return PersonLink(memoryID: MemoryID(rawValue: row["memory_id"]), person: person, saidName: row["role_text"],
                              origin: (row["origin"] as String?).flatMap(LinkOrigin.init(rawValue:)), relation: relation,
                              inPersonsFirstRecording: session == nil || first == nil || session == first)
        }
    }
}
