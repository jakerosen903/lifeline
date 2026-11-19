import Foundation
import GRDB

/// The merge of two people (PC-c): `leaving` joins `staying` in one transaction. Each step reads what it changes
/// inside the write, so a view read before a later change cannot steer it. The rules are in
/// `docs/specs/2026-11-18-people-contacts.md`, "Merging two people", with plan decisions 1, 3 and 6 of
/// `docs/plans/2026-11-19-people-contacts-c.md`.
/// `EntityRepository.merge` joins places and things and refuses people; this is the merge for people.
extension PersonLinkRepository {
    private typealias MergeError = PersonMergeActions.Error

    func checkMerge(_ leaving: PersonID, into staying: PersonID) throws -> PersonMergePreview {
        try db.writer.read { db in try Self.mergePair(leaving, into: staying, in: db).preview }
    }

    func merge(_ leaving: PersonID, into staying: PersonID) throws -> PersonMergeReceipt {
        try db.writer.write { db in try Self.merge(leaving, into: staying, in: db) }
    }

    // MARK: - The pair

    /// The two people and their entities, read inside the caller's transaction.
    private struct MergePair {
        var leaving: Person, staying: Person
        var leavingEntity: Entity, stayingEntity: Entity

        var preview: PersonMergePreview {
            PersonMergePreview(leaving: leaving, staying: staying,
                               staysHidden: leavingEntity.hiddenFromTimeline != stayingEntity.hiddenFromTimeline,
                               staysOutOfAI: leavingEntity.excludedFromAI != stayingEntity.excludedFromAI)
        }
    }

    /// Every refusal, before anything is written: the same person, a person that is gone, the owner (plan decision 5),
    /// and two persons that both hold a contact. The app refuses before the unique contact index does.
    private static func mergePair(_ leaving: PersonID, into staying: PersonID, in db: Database) throws -> MergePair {
        guard leaving != staying else { throw MergeError.samePerson }
        guard let l = try person(leaving, in: db), let s = try person(staying, in: db),
              let le = try Entity.fetchOne(db, key: l.entityID.rawValue), let se = try Entity.fetchOne(db, key: s.entityID.rawValue)
        else { throw MergeError.notFound }
        guard !l.isOwner, !s.isOwner else { throw MergeError.owner }
        guard l.contactIdentifier == nil || s.contactIdentifier == nil else { throw MergeError.twoContacts }
        return MergePair(leaving: l, staying: s, leavingEntity: le, stayingEntity: se)
    }

    private static func person(_ id: PersonID, in db: Database) throws -> Person? {
        try Person.fetchOne(db, sql: Person.selectSQL + "where person.id = ?", arguments: [id.rawValue])
    }

    // MARK: - The merge

    /// The steps run in this order. A person and their entity share one id. Every row still on `leaving` at the end
    /// goes with its entity by cascade: a link or photo the staying person already had, and the person row.
    private static func merge(_ leaving: PersonID, into staying: PersonID, in db: Database) throws -> PersonMergeReceipt {
        let pair = try mergePair(leaving, into: staying, in: db)
        let l = pair.leaving, s = pair.staying
        try moveLinks(from: l.entityID, to: s.entityID, in: db)
        try moveFirstTellings(from: l.entityID, to: s.entityID, in: db)
        try moveNames(of: l, to: s, in: db)
        try movePhotos(from: l.entityID, to: s.entityID, in: db)
        try moveWhatPointsAt(l, to: s, in: db)
        try moveContact(of: l, to: s, in: db)
        try takeValues(pair, in: db)
        _ = try Entity.deleteOne(db, key: l.entityID.rawValue)
        return PersonMergeReceipt(staying: s.id, leaving: l.id, stayingName: s.displayName)
    }

    /// A memory linked to both keeps the stayer's row, with its role text and handle (ruling C2); that row takes the
    /// stronger origin first. Every other link moves as it is: origin, role text and handle travel with the row.
    private static func moveLinks(from l: EntityID, to s: EntityID, in db: Database) throws {
        for link in try MomentEntity.filter(Column("entity_id") == l.rawValue).fetchAll(db) {
            try MomentEntity.raiseOrigin(link.memoryID, s, link.relation, to: link.origin, in: db)
        }
        try db.execute(sql: "update or ignore moment_entity set entity_id = ? where entity_id = ?", arguments: [s.rawValue, l.rawValue])
    }

    /// The leaving person's spans follow the stayer's, in their order, as `EntityRepository.merge` does. The stayer's
    /// first telling stays first; a stayer with none takes the other's.
    private static func moveFirstTellings(from l: EntityID, to s: EntityID, in db: Database) throws {
        let last = try Int.fetchOne(db, sql: #"select max("order") from entity_span where entity_id = ?"#, arguments: [s.rawValue]) ?? -1
        let orders = try Int.fetchAll(db, sql: #"select "order" from entity_span where entity_id = ? order by "order""#, arguments: [l.rawValue])
        for (offset, order) in orders.enumerated() {
            try db.execute(sql: #"update entity_span set entity_id = ?, "order" = ? where entity_id = ? and "order" = ?"#,
                           arguments: [s.rawValue, last + 1 + offset, l.rawValue, order])
        }
    }

    /// Each alias of the leaving person, oldest first, then their name (plan decision 3), so the name said in a later
    /// story still finds the merged person. A name that came from a contact is never an alias: no contact name may reach
    /// the model. A name equal to the stayer's adds nothing, so a contact name the stayer carries is never copied in either.
    private static func moveNames(of l: Person, to s: Person, in db: Database) throws {
        for alias in try Alias.filter(Column("person_id") == l.id.rawValue).order(Column.rowID).fetchAll(db) {
            try PeopleRepository.insertAlias(alias.text, s.id, db)
        }
        guard l.nameOrigin != .contact, PeopleRepository.normalize(l.displayName) != PeopleRepository.normalize(s.displayName) else { return }
        try PeopleRepository.insertAlias(l.displayName, s.id, db)
    }

    /// One page order: the stayer's photos as a read shows them, key photo first, then the other's. A photo on both pages
    /// keeps the stayer's row; when the leaving row is the owner's (origin null), the kept row becomes the owner's too, so a
    /// later "let go" of a story cannot take the photo off. Moved rows are `attached` first: the unique cover index allows
    /// one cover per page and is checked per statement. `writeOrder` then numbers the page and sets its one cover.
    private static func movePhotos(from l: EntityID, to s: EntityID, in db: Database) throws {
        let order = "order by role = 'cover' desc, sort_order, rowid"
        let staying = try String.fetchAll(db, sql: "select photo_id from photo_link where entity_id = ? \(order)", arguments: [s.rawValue])
        let leaving = try String.fetchAll(db, sql: "select photo_id from photo_link where entity_id = ? \(order)", arguments: [l.rawValue])
        guard !leaving.isEmpty else { return }
        try db.execute(sql: """
            update photo_link set origin = null where entity_id = ?
                and photo_id in (select photo_id from photo_link where entity_id = ? and origin is null)
            """, arguments: [s.rawValue, l.rawValue])
        try db.execute(sql: "update photo_link set role = 'attached' where entity_id = ?", arguments: [l.rawValue])
        try db.execute(sql: "update or ignore photo_link set entity_id = ? where entity_id = ?", arguments: [s.rawValue, l.rawValue])
        try PhotoRepository.writeOrder((staying + leaving).map(PhotoID.init(rawValue:)), of: .entity(s), in: db)
    }

    /// Every row that points at the leaving person points at the stayer. Order matters: a stored choice cascades on its
    /// person and a mention is set null, so both move before the delete. A tag has no foreign key, so one the stayer has
    /// already is deleted here, not left behind. A declined contact and a picture-removal marker are both rows of
    /// `contact_declined` and move alike.
    private static func moveWhatPointsAt(_ l: Person, to s: Person, in db: Database) throws {
        let (lp, sp) = (l.id.rawValue, s.id.rawValue)
        if try db.tableExists("photo_page_declined") {
            try db.execute(sql: "update or ignore photo_page_declined set entity_id = ? where entity_id = ?", arguments: [sp, lp])
        }
        try db.execute(sql: "update mention set person_id = ? where person_id = ?", arguments: [sp, lp])
        try db.execute(sql: "update candidate_person_choice set person_id = ? where person_id = ?", arguments: [sp, lp])
        try db.execute(sql: "update curiosity_item set entity_id = ? where entity_id = ?", arguments: [sp, lp])
        try db.execute(sql: "update session set subject_entity_id = ? where subject_entity_id = ?", arguments: [sp, lp])
        let entity = ElementKind.entity.rawValue
        try db.execute(sql: "update or ignore domain_tag set element_id = ? where element_kind = ? and element_id = ?", arguments: [sp, entity, lp])
        try db.execute(sql: "delete from domain_tag where element_kind = ? and element_id = ?", arguments: [entity, lp])
        try db.execute(sql: """
            insert or ignore into contact_declined (person_id, contact_identifier) select ?, contact_identifier from contact_declined where person_id = ?
            """, arguments: [sp, lp])
    }

    /// When only the leaving person holds a contact, the stayer takes it: identifier, kept name, state and the copied
    /// picture. The leaving row lets go first, because the unique contact index is checked per statement.
    private static func moveContact(of l: Person, to s: Person, in db: Database) throws {
        guard let identifier = l.contactIdentifier, s.contactIdentifier == nil else { return }
        try db.execute(sql: """
            update person set contact_identifier = null, contact_name = null, contact_state = null, contact_photo_id = null where id = ?
            """, arguments: [l.id.rawValue])
        try db.execute(sql: "update person set contact_identifier = ?, contact_name = ?, contact_state = ?, contact_photo_id = ? where id = ?",
                       arguments: [identifier, l.contactName, l.contactState, l.contactPhotoID?.rawValue, s.id.rawValue])
    }

    /// The stayer keeps their name, name origin and every value they have; where they have none, they take the other's:
    /// notes, birth date with its origin, the detail line, stated dates. Hidden or kept from the AI on either side stays
    /// on (plan decision 1). The merge is the owner's act, so the stayer is no longer a guess (plan decision 6).
    private static func takeValues(_ pair: MergePair, in db: Database) throws {
        let (l, s) = (pair.leaving, pair.staying)
        let notes = isEmpty(s.notes) ? l.notes : s.notes
        let (birth, birthOrigin) = s.birthDate == nil ? (l.birthDate, l.birthDateOrigin) : (s.birthDate, s.birthDateOrigin)
        try db.execute(sql: "update person set notes = ?, birth_date = ?, birth_date_origin = ?, created_by_guess = 0 where id = ?",
                       arguments: [notes, birth, birthOrigin?.rawValue, s.id.rawValue])
        var entity = pair.stayingEntity
        if isEmpty(entity.detailText) { entity.detailText = pair.leavingEntity.detailText }
        if !entity.range.isPlaced { entity.range = pair.leavingEntity.range }
        entity.hiddenFromTimeline = entity.hiddenFromTimeline || pair.leavingEntity.hiddenFromTimeline
        entity.excludedFromAI = entity.excludedFromAI || pair.leavingEntity.excludedFromAI
        try entity.update(db)
    }

    /// No value: nil, or only space. The page can save an emptied field as empty text.
    private static func isEmpty(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
