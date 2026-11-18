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
    private let db: AppDatabase

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
}
