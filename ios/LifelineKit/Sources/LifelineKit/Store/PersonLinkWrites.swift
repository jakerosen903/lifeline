import Foundation
import GRDB

/// The owner's answers about a person link (Task 5): settle, move, Undo and a choice before Keep.
/// Each runs in one transaction and reads what it changes inside it, so a kill leaves the old
/// state or the new one, and a view read before a later change cannot steer the write.
/// The rules are in `docs/specs/2026-11-18-people-contacts.md`, "Moving a name to another person".
extension PersonLinkRepository {
    typealias Error = PersonLinkActions.Error

    func settle(_ link: PersonLink, wholeGroup: Bool) throws {
        try db.writer.write { db in _ = try Self.settle(link, wholeGroup: wholeGroup, in: db) }
    }

    func move(_ link: PersonLink, to target: PersonLinkActions.Target, wholeGroup: Bool) throws -> PersonMoveReceipt {
        try db.writer.write { db in try Self.move(link, to: target, wholeGroup: wholeGroup, in: db) }
    }

    func undo(_ receipt: PersonMoveReceipt) throws {
        try db.writer.write { db in try Self.undo(receipt, in: db) }
    }

    /// Stores the owner's answer for one said name on a waiting card; a second answer replaces it.
    func storeChoice(_ target: PersonLinkActions.Target, for saidName: String, on candidate: CandidateID) throws {
        let key = SaidName.key(saidName)
        guard !key.isEmpty else { throw Error.notFound }   // no words, nothing Keep could match
        try db.writer.write { db in
            guard let card = try Candidate.fetchOne(db, key: candidate.rawValue), card.kind == .memory else { throw Error.notFound }
            guard card.status == .pending else { throw Error.stale }   // Keep has run: the answer would apply to nothing
            let choice: String, person: PersonID?
            switch target {
            case .person(let id):
                guard try Person.exists(db, key: id.rawValue) else { throw Error.notFound }
                (choice, person) = ("person", id)
            case .someoneNew: (choice, person) = ("new", nil)
            case .notAPerson: (choice, person) = ("not_a_person", nil)
            }
            try db.execute(sql: """
                insert or replace into candidate_person_choice (candidate_id, said_name, choice, person_id, contact_identifier)
                values (?, ?, ?, ?, null)
                """, arguments: [candidate.rawValue, key, choice, person?.rawValue])
        }
    }

    // MARK: - Settle

    private struct Settled {
        var before: [MomentEntity] = [], after: [MomentEntity] = [], addedAliases: [Alias] = [], clearedGuess: PersonMoveReceipt.PersonName?
    }

    /// Origin `confirmed` for the link or its group; the said names become the person's aliases;
    /// the person is no longer a guess. A link already confirmed changes nothing.
    private static func settle(_ link: PersonLink, wholeGroup: Bool, in db: Database) throws -> Settled {
        let current = try current(link, in: db)
        let open = try rows(of: wholeGroup ? group(of: current, in: db) : [current], in: db).filter { $0.origin != .confirmed }
        guard !open.isEmpty else { return Settled() }
        var settled = Settled(before: open)
        for var row in open {
            row.origin = .confirmed
            try setOrigin(row, in: db)
            settled.after.append(row)
        }
        settled.addedAliases = try addAliases(from: open, to: current.person.id, in: db)
        settled.clearedGuess = try clearGuess(current.person, in: db)
        return settled
    }

    /// The owner stands behind this person now: no longer a guess a move may remove. Returns the
    /// person's name as it is, so Undo can see a rename since; nil when there was no flag to clear.
    private static func clearGuess(_ person: Person, in db: Database) throws -> PersonMoveReceipt.PersonName? {
        guard person.createdByGuess else { return nil }
        try db.execute(sql: "update person set created_by_guess = 0 where id = ?", arguments: [person.id.rawValue])
        return PersonMoveReceipt.PersonName(id: person.id, name: person.displayName, origin: person.nameOrigin)
    }

    // MARK: - Move

    private static func move(_ link: PersonLink, to target: PersonLinkActions.Target, wholeGroup: Bool, in db: Database) throws -> PersonMoveReceipt {
        let current = try current(link, in: db)
        let old = current.person
        if case .person(let id) = target, id == old.id {
            let s = try settle(current, wholeGroup: wholeGroup, in: db)
            // A settle moves no first telling. One that changed nothing records nothing, so its Undo does nothing (R25).
            let unchanged = s.before.isEmpty ? [] : try spans(of: [old.entityID], in: db)
            return PersonMoveReceipt(before: s.before, after: s.after, removedPerson: nil, addedAliases: s.addedAliases, createdPerson: nil,
                                     newName: old.displayName, spansBefore: unchanged, spansAfter: unchanged, clearedGuess: s.clearedGuess)
        }
        let group = try group(of: current, in: db)
        var scope = try rows(of: wholeGroup ? group : [current], in: db)
        if current.relation == .mention {
            // A fact whose own mention moves takes its detail along, so the two never part (R23). A fact
            // elsewhere in the recording follows a whole answer only (R19).
            let mentioned = Set(scope.map(\.memoryID))
            let whole = wholeGroup || group.count == 1
            scope += try details(about: current, mentionedIn: mentioned, in: db).filter { whole || mentioned.contains($0.memoryID) }
        }

        let person: Person?
        var created: PersonMoveReceipt.PersonName?
        switch target {
        case .person(let id):
            guard let p = try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ?", arguments: [id.rawValue]) else { throw Error.notFound }
            person = p
        case .someoneNew:
            let p = try newPerson(for: current, in: db)
            (person, created) = (p, PersonMoveReceipt.PersonName(id: p.id, name: p.displayName, origin: p.nameOrigin))
        case .notAPerson:
            person = nil
        }
        let touched = [old.entityID] + (person.map { [$0.entityID] } ?? [])
        let spansBefore = try spans(of: touched, in: db)

        // 1. Each link leaves the old person; the new person's row is written, or kept and confirmed.
        var before = scope, after: [MomentEntity] = []
        for row in scope {
            try delete(row, in: db)
            guard let person else { continue }
            if var existing = try MomentEntity.fetchOne(db, sql: "select * from moment_entity where memory_id = ? and entity_id = ? and relation = ?",
                                                        arguments: [row.memoryID.rawValue, person.entityID.rawValue, row.relation.rawValue]) {
                before.append(existing)
                existing.origin = .confirmed
                try setOrigin(existing, in: db)
                after.append(existing)
            } else {
                var moved = row
                moved.entityID = person.entityID
                moved.origin = .confirmed
                try moved.insert(db)
                after.append(moved)
            }
        }
        // 2. The said names teach the new person; the old person keeps theirs. "Not a person" teaches nothing.
        let added = try person.map { try addAliases(from: scope, to: $0.id, in: db) } ?? []
        // The owner picked this person and gave them the name: no longer a guess (R24).
        let cleared = try person.flatMap { try clearGuess($0, in: db) }
        // 3. First tellings follow the moments.
        let moved = Set(scope.map(\.memoryID))
        try replaceFirstTelling(of: old.entityID, ifFrom: moved, in: db)
        if let person { try giveFirstTelling(to: person.entityID, fromOldestOf: moved, in: db) }
        // 4. Last: an empty guess goes, with its entity, aliases and first telling (they are in `spansBefore`).
        let removed = try removeIfEmptyGuess(old.id, in: db)
        return PersonMoveReceipt(before: before, after: after, removedPerson: removed?.person, addedAliases: added, createdPerson: created?.id,
                                 newName: person?.displayName ?? "", removedEntity: removed?.entity, removedAliases: removed?.aliases ?? [],
                                 spansBefore: spansBefore, spansAfter: try spans(of: touched, in: db), clearedGuess: cleared, createdName: created)
    }

    /// "Someone new": a person named by the said name. The owner chose them, so they are not a guess (R14).
    private static func newPerson(for link: PersonLink, in db: Database) throws -> Person {
        let said = try saidName(of: link.memoryID, ref: link.saidName, in: db)
        // An older link with no said name has only the person's name to go by.
        let name = (said?.name ?? said?.relation ?? link.person.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        let person = Person(id: .init(), displayName: name, notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                            nameOrigin: .said, createdByGuess: false)
        try person.insertWithEntity(db)
        try PeopleRepository.insertAlias(name, person.id, db)
        return person
    }

    /// The facts, feelings and goals of the link's session that are details of its person, and either
    /// sit in a memory of `mentioned` (a detail the model linked by a person id, R38) or have a card
    /// whose `about_ref` is a person mention with the link's said name. A detail placed by hand in
    /// another memory has no such card ref and stays.
    private static func details(about link: PersonLink, mentionedIn mentioned: Set<MemoryID>, in db: Database) throws -> [MomentEntity] {
        guard let session = try session(of: link.memoryID, in: db) else { return [] }
        let said = link.saidName.map { SaidName(ref: $0) }
        // An older link with no said name matches no card ref; only its own memories' details go.
        let keys = Set(said.map { [SaidName.key($0.raw)] + ($0.name.map { [SaidName.key($0)] } ?? []) } ?? []).subtracting([""])
        let candidates = try fetch(where: "person.id = ? and me.relation = 'detail' and \(sessionSQL) = ?",
                                   arguments: [link.person.id.rawValue, session], order: "memory.created_at, me.memory_id", in: db)
        return try rows(of: try candidates.filter { candidate in
            if mentioned.contains(candidate.memoryID) { return true }
            guard !keys.isEmpty else { return false }
            return try aboutMentionText(of: candidate.memoryID, in: db).map { keys.contains(SaidName.key($0)) } == true
        }, in: db)
    }

    /// The text of the person mention a memory's card is about, when its `about_ref` names one.
    private static func aboutMentionText(of memory: MemoryID, in db: Database) throws -> String? {
        guard let card = try Candidate.fetchOne(db, sql: "select candidate.* from candidate join memory on memory.created_from_candidate_id = candidate.id where memory.id = ?",
                                                arguments: [memory.rawValue]),
              let about = CandidatePayload.memory(card)?.aboutRef else { return nil }
        return try Candidate.fetchAll(db, sql: "select * from candidate where segment_id = ? and kind = 'person'", arguments: [card.segmentID.rawValue])
            .compactMap(CandidatePayload.mention).first { $0.ref == about }?.text
    }

    // MARK: - First tellings

    /// When the entity's first telling came from one of `moved`, it takes the first span of its
    /// oldest remaining moment, or goes when none remains (R28). A moment is a mention in an
    /// event or other memory that is not hidden: a fact or a hidden memory never becomes the first telling.
    private static func replaceFirstTelling(of entity: EntityID, ifFrom moved: Set<MemoryID>, in db: Database) throws {
        guard let first = try EntitySpan.fetchOne(db, sql: #"select * from entity_span where entity_id = ? and "order" = 0"#, arguments: [entity.rawValue]) else { return }
        let fromMoved = try moved.contains { memory in
            try firstSpan(of: memory, in: db).map { $0.segmentID == first.segmentID && $0.startMs == first.startMs && $0.endMs == first.endMs } == true
        }
        guard fromMoved else { return }
        let next = try MemorySpan.fetchOne(db, sql: """
            select ms.* from moment_entity me join memory on memory.id = me.memory_id
            join memory_span ms on ms.memory_id = memory.id and ms."order" = 0
            where me.entity_id = ? and me.relation = 'mention' and memory.kind in ('event', 'other') and memory.hidden_from_timeline = 0
            order by memory.created_at, memory.id limit 1
            """, arguments: [entity.rawValue])
        if let next {
            try db.execute(sql: #"update entity_span set segment_id = ?, start_ms = ?, end_ms = ? where entity_id = ? and "order" = 0"#,
                           arguments: [next.segmentID.rawValue, next.startMs, next.endMs, entity.rawValue])
        } else {
            try db.execute(sql: #"delete from entity_span where entity_id = ? and "order" = 0"#, arguments: [entity.rawValue])
        }
    }

    /// A first telling from the oldest of `memories`, only when the entity has none (`giveFirstTelling`'s rule).
    private static func giveFirstTelling(to entity: EntityID, fromOldestOf memories: Set<MemoryID>, in db: Database) throws {
        let oldest = try memories.compactMap { id -> (Date, String, MemorySpan)? in
            guard let created = try Date.fetchOne(db, sql: "select created_at from memory where id = ?", arguments: [id.rawValue]),
                  let span = try firstSpan(of: id, in: db) else { return nil }
            return (created, id.rawValue, span)
        }.min { ($0.0, $0.1) < ($1.0, $1.1) }
        guard let span = oldest?.2 else { return }
        try EntitySpan(entityID: entity, segmentID: span.segmentID, startMs: span.startMs, endMs: span.endMs, order: 0).insertIgnoringDuplicate(db)
    }

    private static func firstSpan(of memory: MemoryID, in db: Database) throws -> MemorySpan? {
        try MemorySpan.fetchOne(db, sql: #"select * from memory_span where memory_id = ? and "order" = 0"#, arguments: [memory.rawValue])
    }

    private static func spans(of entities: [EntityID], in db: Database) throws -> [EntitySpan] {
        try EntitySpan.filter(entities.map(\.rawValue).contains(Column("entity_id"))).fetchAll(db).sorted(by: spanOrder)
    }

    private static func spanOrder(_ a: EntitySpan, _ b: EntitySpan) -> Bool {
        (a.entityID.rawValue, a.order) < (b.entityID.rawValue, b.order)
    }

    // MARK: - The empty guess

    /// Deletes a person the guess made that nothing holds any more: no link, photo, contact the owner
    /// linked, name the owner gave, mention, choice, tag, curiosity or session subject. A person the owner
    /// edited (a typed name, stated dates, hidden or kept from the AI) stays (R39). A person Keep made from
    /// a contact is still the app's guess and may go with that contact (PB2). Returns what Undo needs.
    /// The pre-v10 link table is not checked: only v15 Keep makes a guessed person, and it never writes there.
    private static func removeIfEmptyGuess(_ id: PersonID, in db: Database) throws -> (person: Person, entity: Entity, aliases: [Alias])? {
        guard let person = try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ?", arguments: [id.rawValue]),
              person.createdByGuess, !person.isOwner, person.contactPhotoID == nil,
              (person.nameOrigin == .said && person.contactIdentifier == nil) || person.isGuessFromContact,
              let entity = try Entity.fetchOne(db, key: person.entityID.rawValue),
              entity.range == .unplaced, !entity.hiddenFromTimeline, !entity.excludedFromAI else { return nil }
        let held = try Int.fetchOne(db, sql: """
            select (select count(*) from moment_entity where entity_id = :e) + (select count(*) from photo_link where entity_id = :e)
                 + (select count(*) from mention where person_id = :p)
                 + (select count(*) from candidate_person_choice where person_id = :p) + (select count(*) from contact_declined where person_id = :p)
                 + (select count(*) from curiosity_item where entity_id = :e) + (select count(*) from session where subject_entity_id = :e)
                 + (select count(*) from domain_tag where element_kind = 'entity' and element_id = :e)
            """, arguments: ["e": entity.id.rawValue, "p": id.rawValue]) ?? 1
        guard held == 0 else { return nil }
        // Oldest first, so Undo puts them back in the order the packet reads them.
        let aliases = try Alias.filter(Column("person_id") == id.rawValue).order(Column.rowID).fetchAll(db)
        _ = try Entity.deleteOne(db, key: entity.id.rawValue)   // the person, aliases and spans go by cascade
        return (person, entity, aliases)
    }

    // MARK: - Undo

    /// Refused unless the rows the move left are exactly as it left them, the rows it deleted are
    /// still gone, and a person it made holds nothing else. Then every row goes back.
    private static func undo(_ r: PersonMoveReceipt, in db: Database) throws {
        for row in r.after where try fetchRow(row, in: db) != row { throw Error.stale }
        // A memory or person deleted since leaves nowhere to put a row back (R27).
        for memory in Set(r.before.map(\.memoryID.rawValue)) where try !Memory.exists(db, key: memory) { throw Error.stale }
        for entity in Set(r.before.map(\.entityID)) where entity != r.removedEntity?.id {
            if try !Entity.exists(db, key: entity.rawValue) { throw Error.stale }
        }
        // A person Undo would mark as a guess again, or delete, must not have been renamed since (R26).
        for recorded in [r.clearedGuess, r.createdName].compactMap({ $0 }) {
            let now = try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ?", arguments: [recorded.id.rawValue])
            if now?.displayName != recorded.name || now?.nameOrigin != recorded.origin { throw Error.stale }
        }
        let afterKeys = Set(r.after.map(key))
        for row in r.before where !afterKeys.contains(key(row)) {
            if try fetchRow(row, in: db) != nil { throw Error.stale }
        }
        var touched = Set((r.before + r.after).map(\.entityID))
        if let removed = r.removedEntity {
            touched.insert(removed.id)
            if try Entity.exists(db, key: removed.id.rawValue) { throw Error.stale }
        }
        // One contact, one person: refuse before the unique index does, when another person holds the contact now.
        if let contact = r.removedPerson?.contactIdentifier,
           (try Int.fetchOne(db, sql: "select count(*) from person where contact_identifier = ?", arguments: [contact]) ?? 0) > 0 { throw Error.stale }
        if let created = r.createdPerson {
            touched.insert(EntityID(rawValue: created.rawValue))
            let links = try Int.fetchOne(db, sql: "select count(*) from moment_entity where entity_id = ?", arguments: [created.rawValue]) ?? 0
            let photos = try Int.fetchOne(db, sql: "select count(*) from photo_link where entity_id = ?", arguments: [created.rawValue]) ?? 0
            if links != r.after.filter({ $0.entityID.rawValue == created.rawValue }).count || photos > 0 { throw Error.stale }
        }
        let touchedIDs = Array(touched).sorted { $0.rawValue < $1.rawValue }
        if try spans(of: touchedIDs, in: db) != r.spansAfter.sorted(by: spanOrder) { throw Error.stale }

        for row in r.after { try delete(row, in: db) }
        if let person = r.removedPerson, let entity = r.removedEntity {
            try entity.insert(db)
            try person.insert(db)
            for alias in r.removedAliases { try alias.insert(db) }
        }
        try db.execute(sql: "delete from entity_span where entity_id in (\(touchedIDs.map { _ in "?" }.joined(separator: ",")))",
                       arguments: StatementArguments(touchedIDs.map(\.rawValue)))
        for span in r.spansBefore { try span.insert(db) }
        for row in r.before { try row.insert(db) }
        for alias in r.addedAliases {
            try db.execute(sql: "delete from alias where person_id = ? and text = ?", arguments: [alias.personID.rawValue, alias.text])
        }
        if let created = r.createdPerson { _ = try Entity.deleteOne(db, key: created.rawValue) }
        if let person = r.clearedGuess {
            try db.execute(sql: "update person set created_by_guess = 1 where id = ?", arguments: [person.id.rawValue])
        }
    }

    // MARK: - Rows

    /// The link as stored now, read again so a stale view cannot steer the write.
    private static func current(_ link: PersonLink, in db: Database) throws -> PersonLink {
        guard let row = try fetch(where: "me.memory_id = ? and person.id = ? and me.relation = ?",
                                  arguments: [link.memoryID.rawValue, link.person.id.rawValue, link.relation.rawValue],
                                  order: "me.memory_id", in: db).first else { throw Error.notFound }
        return row
    }

    private static func rows(of links: [PersonLink], in db: Database) throws -> [MomentEntity] {
        try links.compactMap { link in
            try MomentEntity.fetchOne(db, sql: "select * from moment_entity where memory_id = ? and entity_id = ? and relation = ?",
                                      arguments: [link.memoryID.rawValue, link.person.entityID.rawValue, link.relation.rawValue])
        }
    }

    private static func fetchRow(_ row: MomentEntity, in db: Database) throws -> MomentEntity? {
        try MomentEntity.fetchOne(db, sql: "select * from moment_entity where memory_id = ? and entity_id = ? and relation = ?",
                                  arguments: [row.memoryID.rawValue, row.entityID.rawValue, row.relation.rawValue])
    }

    private static func key(_ row: MomentEntity) -> String { "\(row.memoryID.rawValue)|\(row.entityID.rawValue)|\(row.relation.rawValue)" }

    private static func delete(_ row: MomentEntity, in db: Database) throws {
        try db.execute(sql: "delete from moment_entity where memory_id = ? and entity_id = ? and relation = ?",
                       arguments: [row.memoryID.rawValue, row.entityID.rawValue, row.relation.rawValue])
    }

    private static func setOrigin(_ row: MomentEntity, in db: Database) throws {
        try db.execute(sql: "update moment_entity set origin = ? where memory_id = ? and entity_id = ? and relation = ?",
                       arguments: [row.origin?.rawValue, row.memoryID.rawValue, row.entityID.rawValue, row.relation.rawValue])
    }

    // MARK: - Aliases

    /// The said name of each row and the relation phrase its card gave, as aliases of `person`.
    /// A group phrase is never one person's name. Returns only the aliases that are new.
    private static func addAliases(from rows: [MomentEntity], to person: PersonID, in db: Database) throws -> [Alias] {
        var added: [Alias] = []
        for row in rows {
            guard let said = try saidName(of: row.memoryID, ref: row.roleText, in: db) else { continue }
            for text in [said.name, said.relation].compactMap({ $0 }) where !GroupPhrase.isGroup(text) {
                if try PeopleRepository.insertAlias(text, person, db) { added.append(Alias(personID: person, text: text.trimmingCharacters(in: .whitespacesAndNewlines))) }
            }
        }
        return added
    }

    /// A link's said name, with the relation phrase a person card of the memory's segments gave it,
    /// as Keep reads it (`GuessInputs.saidName`). Nil for a link with no words.
    private static func saidName(of memory: MemoryID, ref: String?, in db: Database) throws -> SaidName? {
        guard let ref, !SaidName.key(ref).isEmpty else { return nil }
        let relation = try Candidate.fetchAll(db, sql: """
            select * from candidate where kind = 'person' and segment_id in (select segment_id from memory_span where memory_id = ?)
            order by ordinal
            """, arguments: [memory.rawValue])
            .compactMap(CandidatePayload.mention)
            .first { PeopleRepository.normalize($0.text) == PeopleRepository.normalize(ref) && !($0.relationText ?? "").trimmingCharacters(in: .whitespaces).isEmpty }?
            .relationText
        return SaidName(ref: ref, mentionRelation: relation)
    }
}
