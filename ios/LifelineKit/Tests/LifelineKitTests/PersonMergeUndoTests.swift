import Foundation
import GRDB
import Testing
@testable import LifelineKit

// PC-c Task 3: Undo puts every row back from the merge's receipt, or refuses and changes nothing.
// Sample names are invented.

extension MergeEnv {
    /// The rows of both persons, as `RowCopy` reads them: the owned tables, both person and entity rows, and every row
    /// a merge can point at the stayer. Rowid order counts in the owned tables, so a row put back out of order shows.
    /// The leaving person's own row comes back with a new rowid, so each person row is read alone.
    func rows(of a: Person, _ b: Person) throws -> [RowCopy] {
        try db.writer.read { db in
            let ids: StatementArguments = [a.id.rawValue, b.id.rawValue]
            let byEntity = "entity_id in (?, ?)"
            return [
                try RowCopy.read("person", where: "id = ?", arguments: [a.id.rawValue], in: db),
                try RowCopy.read("person", where: "id = ?", arguments: [b.id.rawValue], in: db),
                try RowCopy.read("entity", where: "id = ?", arguments: [a.id.rawValue], in: db),
                try RowCopy.read("entity", where: "id = ?", arguments: [b.id.rawValue], in: db),
                try RowCopy.read("moment_entity", where: byEntity, arguments: ids, in: db),
                try RowCopy.read("entity_span", where: byEntity, arguments: ids, in: db),
                try RowCopy.read("alias", where: "person_id in (?, ?)", arguments: ids, in: db),
                try RowCopy.read("photo_link", where: byEntity, arguments: ids, in: db),
                try RowCopy.read("domain_tag", where: "element_kind = 'entity' and element_id in (?, ?)", arguments: ids, in: db),
                try RowCopy.read("contact_declined", where: "person_id in (?, ?)", arguments: ids, in: db),
                try RowCopy.read("photo_page_declined", where: byEntity, arguments: ids, in: db),
                try RowCopy.read("memory_person", where: "person_id in (?, ?)", arguments: ids, in: db),
                try RowCopy.read("mention", where: "1", arguments: [], in: db),
                try RowCopy.read("candidate_person_choice", where: "1", arguments: [], in: db),
                try RowCopy.read("curiosity_item", where: "1", arguments: [], in: db),
                try RowCopy.read("session", where: "1", arguments: [], in: db),
            ]
        }
    }
}

/// The merge tests of Task 2 that change rows, each as the state before a merge of Robin into Robyn Vale.
enum MergeCase: String, CaseIterable, Sendable {
    case links, linkedToBoth, names, contact, values, photos, sharedPhoto, pageDeclines, whatPointsAt, firstTellings

    func build(_ env: MergeEnv) throws -> (leaving: Person, staying: Person) {
        let robin = try env.store.people.insertPerson(displayName: "Robin")
        let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
        let (r, s) = (robin.id.rawValue, robyn.id.rawValue)
        switch self {
        case .links:
            let (a, b, fact) = (try env.memory("Robin painted the fence"), try env.memory("Robin fixed the gate"), try env.memory("Robin is a carpenter"))
            try env.link(a, robin, role: "Robin", origin: .assumed)
            try env.link(b, robin, role: "my roommate", origin: .confirmed)
            try env.link(fact, robin, .detail, role: nil, origin: .confirmed)
            try env.link(try env.memory("Robyn cut the grass"), robyn, role: "Robyn", origin: .said)
        case .linkedToBoth:
            let (m, n) = (try env.memory("Robin and Robyn painted the fence"), try env.memory("Robin and Robyn fixed the gate"))
            try env.link(m, robin, role: "Robin", origin: .confirmed)
            try env.link(m, robyn, role: "Robyn", origin: .assumed)
            try env.link(n, robin, role: "my roommate", origin: .assumed)
            try env.link(n, robyn, role: nil, origin: .said)
        case .names:
            try env.store.people.addAlias("Rob", to: robin.id)
            try env.store.people.addAlias("my roommate", to: robin.id)
            try env.store.people.addAlias("Vale", to: robyn.id)
        case .contact:
            let picture = MergeEnv.photo("vale")
            try env.store.photos.insert(picture, linkingTo: .entity(robin.entityID))
            try env.sql("update person set contact_identifier = 'c-vale', contact_name = 'Robyn Vale', contact_state = 'linked', contact_photo_id = ?, name_origin = 'contact' where id = ?",
                        [picture.id.rawValue, r])
            try env.sql("insert into contact_declined (person_id, contact_identifier) values (?, 'c-vale'), (?, 'picture:c-vale')", [s, s])
        case .values:
            try env.sql("update person set notes = 'Plays the cello', birth_date = ?, birth_date_origin = 'stated' where id = ?",
                        [Date(timeIntervalSince1970: 500_000_000), r])
            try env.sql("update person set notes = '  ', created_by_guess = 1 where id = ?", [s])
            try env.sql("update entity set detail_text = 'a carpenter' where id = ?", [r])
            try env.store.entities.setStatedSpan(robin.entityID, .stated(between: 1990, and: 1995))
            try env.store.entities.setExcluded(robin.entityID, true)
            try env.store.entities.setHidden(robyn.entityID, true)
        case .photos:
            _ = try env.photo("s1", on: robyn)
            let s2 = try env.photo("s2", on: robyn)
            try env.store.photos.setCover(s2, of: .entity(robyn.entityID))
            let shared = try env.photo("shared", on: robyn)
            _ = try env.photo("l1", on: robin)
            try env.store.photos.link(shared, to: .entity(robin.entityID))
            let l2 = try env.photo("l2", on: robin)
            try env.store.photos.setCover(l2, of: .entity(robin.entityID))
        case .sharedPhoto:
            let shared = try env.photo("shared", on: robyn)
            try env.sql("update photo_link set origin = 'story' where photo_id = ?", [shared.rawValue])
            try env.store.photos.link(shared, to: .entity(robin.entityID))
        case .pageDeclines:
            let onStayer = try env.photo("s1", on: robyn), onLeaving = try env.photo("l1", on: robin)
            let neither = MergeEnv.photo("p")
            try env.store.photos.insert(neither)
            try env.sql("insert into photo_page_declined (photo_id, entity_id) values (?, ?), (?, ?), (?, ?)",
                        [onStayer.rawValue, r, onLeaving.rawValue, s, neither.id.rawValue, r])
        case .whatPointsAt:
            let card = try env.card(in: try env.session(["Theo painted the fence"])[0], people: ["Theo"])
            try PersonLinkActions(store: env.store).choose(.person(robin.id), for: "Theo", on: card.id)
            let (session, segments) = try StoreFixtures.session(in: env.store.sessions, segments: ["Robin painted the fence"])
            try env.store.people.insertMention(Mention(id: .init(), segmentID: segments[0].id, text: "Robin", status: .resolved, personID: robin.id))
            let item = CuriosityItem(id: .init(), kind: .personWithoutMoment, text: "When did you meet Robin?", payoffCount: 0, status: .open,
                                     sourceMemoryID: nil, targetMemoryID: nil, entityID: robin.entityID)
            try env.db.writer.write { try item.insert($0) }
            try env.sql("update session set subject_entity_id = ? where id = ?", [r, session.rawValue])
            try env.store.tags.tag(.entity, r, "family")
            try env.store.tags.tag(.entity, r, "school")
            try env.store.tags.tag(.entity, s, "family")
            try env.sql("insert into contact_declined (person_id, contact_identifier) values (?, 'c-other'), (?, 'c-other'), (?, 'picture:c-hale')", [r, s, r])
        case .firstTellings:
            let segments = try env.session(["Robyn cut the grass", "Robin painted the fence", "Robin fixed the gate"])
            try env.store.entities.insertSpan(EntitySpan(entityID: robyn.entityID, segmentID: segments[0], startMs: 0, endMs: 900, order: 0))
            try env.store.entities.insertSpan(EntitySpan(entityID: robin.entityID, segmentID: segments[1], startMs: 100, endMs: 800, order: 0))
            try env.store.entities.insertSpan(EntitySpan(entityID: robin.entityID, segmentID: segments[2], startMs: 50, endMs: 700, order: 1))
        }
        return (robin, robyn)
    }
}

// MARK: - Undo restores every row

@Test(arguments: MergeCase.allCases)
func undoPutsEveryRowOfBothPeopleBack(_ mergeCase: MergeCase) throws {
    let env = try MergeEnv()
    let (robin, robyn) = try mergeCase.build(env)
    let rows = try env.rows(of: robin, robyn), dump = try env.dump()

    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    #expect(try env.rows(of: robin, robyn) != rows, "the merge changed something")
    try env.actions.undo(receipt)

    #expect(try env.rows(of: robin, robyn) == rows)
    #expect(try env.dump() == dump)
}

// Review Focus 2: both links come back, each with its own origin and role text.
@Test func undoBringsBackBothLinksWithTheirOwnOriginsAndRoleTexts() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let m = try env.memory("Robin and Robyn painted the fence")
    try env.link(m, robin, role: "my roommate", origin: .confirmed)
    try env.link(m, robyn, role: nil, origin: .assumed)

    try env.actions.undo(try env.actions.merge(robin.id, into: robyn.id))

    let links = try env.store.entities.links(of: m.id).filter { $0.entity.type == .person }.map(\.link)
        .map { "\($0.entityID == robin.entityID ? "Robin" : "Robyn")|\($0.roleText ?? "-")|\($0.origin?.rawValue ?? "-")" }
    #expect(Set(links) == ["Robin|my roommate|confirmed", "Robyn|-|assumed"])
}

@Test func undoPutsBackADeclineRowMadeByHand() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let photo = MergeEnv.photo("p")
    try env.store.photos.insert(photo)
    try env.sql("insert into photo_page_declined (photo_id, entity_id) values (?, ?)", [photo.id.rawValue, robin.id.rawValue])

    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    #expect(try !env.store.photos.isDeclined(photo.id, on: robin.entityID))
    try env.actions.undo(receipt)

    #expect(try env.store.photos.isDeclined(photo.id, on: robin.entityID))
    #expect(try !env.store.photos.isDeclined(photo.id, on: robyn.entityID))
}

// The legacy `memory_person` rows (kept from v10, read nowhere) go with the leaving person by cascade; Undo gives them
// back, and the stayer's own rows come through unchanged.
@Test func undoGivesBackTheLegacyMemoryPersonRows() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let (m, n) = (try env.memory("Robin painted the fence"), try env.memory("Robyn cut the grass"))
    try env.sql("insert into memory_person (memory_id, person_id, role_text) values (?, ?, 'my roommate'), (?, ?, null), (?, ?, 'Robyn')",
                [m.id.rawValue, robin.id.rawValue, n.id.rawValue, robin.id.rawValue, n.id.rawValue, robyn.id.rawValue])
    let count = { (person: Person) in
        try env.db.writer.read { try Int.fetchOne($0, sql: "select count(*) from memory_person where person_id = ?", arguments: [person.id.rawValue]) ?? 0 }
    }
    let rows = try env.rows(of: robin, robyn), dump = try env.dump()

    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    #expect(try count(robin) == 0 && count(robyn) == 1, "the merge does not move them; the cascade takes the leaving rows")
    try env.actions.undo(receipt)

    #expect(try env.rows(of: robin, robyn) == rows)
    #expect(try env.dump() == dump)
}

// A failure Undo cannot see in advance rolls back: the candidate the leaving entity came from is deleted after the merge,
// so putting the entity back breaks its foreign key. Nothing changes.
@Test func aFailureInsideUndoChangesNothing() throws {
    let env = try MergeEnv()
    let (robin, robyn) = try MergeCase.links.build(env)
    let card = try env.card(in: try env.session(["Robin waved"])[0], people: ["Robin"])
    try env.sql("update entity set created_from_candidate_id = ? where id = ?", [card.id.rawValue, robin.id.rawValue])
    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    try env.sql("delete from candidate where id = ?", [card.id.rawValue])
    let dump = try env.dump()

    #expect(throws: DatabaseError.self) { try env.actions.undo(receipt) }
    #expect(try env.dump() == dump)
}

// Rulings C2 and C11: both rows come back, each with its own handle, whether the merge moved a link or dropped one.
@Test(arguments: [false, true])
func undoBringsBackEachLinkWithItsOwnHandle(oneMemory: Bool) throws {
    let env = try MergeEnv()
    let (leaving, staying, _) = oneMemory ? try env.handlesOnOneMemory() : try env.handlesOnTwoMemories()
    let handles = { (person: Person) in try env.store.entities.links(to: person.entityID).compactMap(\.personHandle) }
    let (leavingHandle, stayingHandle) = (oneMemory ? "p2" : "p1", oneMemory ? "p1" : "p2")
    #expect(try handles(leaving) == [leavingHandle] && handles(staying) == [stayingHandle])
    let rows = try env.rows(of: leaving, staying), dump = try env.dump()

    try env.actions.undo(try env.actions.merge(leaving.id, into: staying.id))

    #expect(try handles(leaving) == [leavingHandle] && handles(staying) == [stayingHandle])
    #expect(try env.rows(of: leaving, staying) == rows)
    #expect(try env.dump() == dump)
}

// MARK: - Stale: Undo refuses and changes nothing

/// Merges a pair with one link each, makes `change` after the merge, and expects Undo to refuse with no row changed.
private func expectStale(_ change: (MergeEnv, _ leaving: Person, _ staying: Person, _ leavingMemory: Memory) throws -> Void) throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let m = try env.memory("Robin painted the fence")
    try env.link(m, robin, role: "Robin", origin: .confirmed)
    _ = try env.photo("s1", on: robyn)
    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    try change(env, robin, robyn, m)
    let dump = try env.dump()

    #expect(throws: PersonMergeActions.Error.stale) { try env.actions.undo(receipt) }
    #expect(try env.dump() == dump)
}

// Review Focus 4.
@Test func undoAfterARenameIsStale() throws {
    try expectStale { env, _, robyn, _ in try env.store.people.rename(robyn.id, to: "Robyn Hale") }
}

@Test func undoAfterANewLinkIsStale() throws {
    try expectStale { env, _, robyn, _ in try env.link(try env.memory("Robyn cut the grass"), robyn, origin: .confirmed) }
}

@Test func undoAfterANewPhotoIsStale() throws {
    try expectStale { env, _, robyn, _ in _ = try env.photo("new", on: robyn) }
}

@Test func undoAfterAMemoryOfTheLeavingPersonIsDeletedIsStale() throws {
    try expectStale { env, _, _, memory in try env.store.memories.delete(memory.id) }
}

@Test func undoAfterARepointedRowIsGoneIsStale() throws {
    let env = try MergeEnv()
    let robin = try env.store.people.insertPerson(displayName: "Robin")
    let robyn = try env.store.people.insertPerson(displayName: "Robyn Vale")
    let segment = try env.session(["Robin painted the fence"])[0]
    let mention = Mention(id: .init(), segmentID: segment, text: "Robin", status: .resolved, personID: robin.id)
    try env.store.people.insertMention(mention)
    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    try env.sql("delete from mention where id = ?", [mention.id.rawValue])
    let dump = try env.dump()

    #expect(throws: PersonMergeActions.Error.stale) { try env.actions.undo(receipt) }
    #expect(try env.dump() == dump)
}

@Test func undoTwiceIsStaleTheSecondTime() throws {
    let env = try MergeEnv()
    let (robin, robyn) = try MergeCase.links.build(env)
    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    try env.actions.undo(receipt)
    let dump = try env.dump()

    #expect(throws: PersonMergeActions.Error.stale) { try env.actions.undo(receipt) }
    #expect(try env.dump() == dump)
}

@Test func undoWhenAnotherPersonHoldsTheLeavingContactIsStale() throws {
    let env = try MergeEnv()
    let (robin, robyn) = try MergeCase.contact.build(env)
    let receipt = try env.actions.merge(robin.id, into: robyn.id)
    try env.store.people.unlinkContact(robyn.id)
    let theo = try env.store.people.insertPerson(displayName: "Theo")
    try env.sql("update person set contact_identifier = 'c-vale', contact_name = 'Robyn Vale', contact_state = 'linked' where id = ?", [theo.id.rawValue])
    let dump = try env.dump()

    #expect(throws: PersonMergeActions.Error.stale) { try env.actions.undo(receipt) }
    #expect(try env.dump() == dump)
}
