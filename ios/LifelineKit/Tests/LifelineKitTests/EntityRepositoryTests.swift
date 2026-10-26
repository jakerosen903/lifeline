import Foundation
import GRDB
import Testing
@testable import LifelineKit

// M7, PR B: entities, the one link table, domain tags.

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }
private func guess(_ y: Int) -> TimeRange {
    TimeRange(earliest: d("\(y)-01-01"), latest: d("\(y)-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: "around then")
}

/// A v9 database with the shape a person's phone has before M7's entities.
func populatedV9aQueue() throws -> DatabaseQueue {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v9")
    try queue.write { db in
        try db.execute(sql: """
            insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1);
            insert into segment (id, session_id, "index", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 9000, 'hi', 'extracted');
            insert into person (id, display_name, is_owner) values ('owner', 'Sam', 1);
            insert into person (id, display_name, is_owner) values ('p1', 'Maya', 0);
            insert into person (id, display_name, is_owner) values ('p2', 'Rosa', 0);
            insert into alias (person_id, text) values ('p1', 'my sister');
            insert into place (id, name_text) values ('pl1', 'Lisbon');
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01 10:00:00');
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m2', 'B', 'b', 'timeline', '2026-10-02 10:00:00');
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m3', 'C', 'c', 'timeline', '2026-10-03 10:00:00');
            insert into memory_span (memory_id, segment_id, start_ms, end_ms, "order") values ('m1', 'g1', 0, 1000, 0);
            insert into memory_span (memory_id, segment_id, start_ms, end_ms, "order") values ('m2', 'g1', 2000, 3000, 0);
            insert into memory_span (memory_id, segment_id, start_ms, end_ms, "order") values ('m3', 'g1', 4000, 5000, 0);
            insert into memory_person (memory_id, person_id, role_text) values ('m1', 'p1', 'my sister');
            insert into memory_person (memory_id, person_id, role_text) values ('m2', 'p1', null);
            insert into memory_person (memory_id, person_id, role_text) values ('m3', 'p2', null);
            insert into memory_place (memory_id, place_id) values ('m3', 'pl1');
            insert into memory_place (memory_id, place_id) values ('m2', 'pl1');
            """)
    }
    return queue
}

@Test func v10OnAPopulatedV8KeepsEveryLink() throws {
    let queue = try populatedV9aQueue()
    try Migrations.migrator.migrate(queue)
    try queue.read { db in
        let types = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "select id, type from entity").map { ($0["id"] as String, $0["type"] as String) })
        #expect(types == ["owner": "person", "p1": "person", "p2": "person", "pl1": "place"])
        #expect(try String.fetchOne(db, sql: "select title from entity where id = 'p1'") == "Maya")
        let links = try Row.fetchAll(db, sql: "select memory_id, entity_id, relation, role_text from moment_entity order by memory_id, entity_id")
            .map { "\($0["memory_id"] as String)-\($0["entity_id"] as String)-\($0["relation"] as String)-\(($0["role_text"] as String?) ?? "")" }
        #expect(links == ["m1-p1-mention-my sister", "m2-p1-mention-", "m2-pl1-mention-", "m3-p2-mention-", "m3-pl1-mention-"])
        #expect(try String.fetchAll(db, sql: "select entity_id from person order by id") == ["owner", "p1", "p2"])
        let span = try Row.fetchOne(db, sql: "select segment_id, start_ms from entity_span where entity_id = 'pl1'")
        #expect(span?["start_ms"] as Int? == 2000, "the place takes the primary span of the first memory that linked it (m2, the older)")
        #expect(try Int.fetchOne(db, sql: "select count(*) from alias") == 1, "aliases are untouched")
    }
}

@Test func entityLinksAndSpans() throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    let (session, _) = try StoreFixtures.session(in: store.sessions, segments: ["the house had a blue door", "we painted the house", "the house was cold"])
    let segments = try store.sessions.segments(in: session)
    let detail = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[0].id, title: "Blue door")
    let early = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[1].id, title: "Painting")
    let fact = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[2].id, title: "Cold")
    try store.memories.updateRange(early.id, guess(1993))
    try store.memories.updateRange(fact.id, guess(1998))
    try store.memories.setKind(fact.id, .fact)

    let house = try store.entities.insert(type: .thing, title: "the house")
    #expect(try store.entities.insert(type: .thing, title: "The House ").id == house.id, "the same thing named twice is one thing")
    #expect(try store.entities.insert(type: .place, title: "the house").id != house.id, "a place of the same name is another entity")
    try store.entities.link(detail.id, house.id, relation: .detail)
    try store.entities.link(early.id, house.id, relation: .mention)
    try store.entities.link(fact.id, house.id, relation: .detail)
    try store.entities.link(early.id, house.id, relation: .mention)   // no-op

    #expect(try store.entities.details(of: house.id).map(\.title) == ["Blue door", "Cold"])
    #expect(try store.entities.moments(of: house.id).map(\.title) == ["Painting"])
    #expect(try store.entities.links(of: early.id).map(\.entity.id) == [house.id])

    let derived = try store.entities.derivedSpan(of: house.id)
    #expect(derived.earliest?.year == 1993 && derived.latest?.year == 1998, "a fact's hidden range counts toward the span")
    #expect(derived.origin == .inferred, "guesses stay guesses")

    let stated = TimeRange(earliest: d("1990-01-01"), latest: d("2001-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .stated, evidenceText: "1990–2001")
    try store.entities.setStatedSpan(house.id, stated)
    #expect(try store.entities.span(of: house.id) == stated, "a stated span wins")
    #expect(try store.entities.entity(id: house.id)?.range == stated, "it round-trips through the row")

    try store.memories.delete(early.id)
    #expect(try store.entities.moments(of: house.id).isEmpty, "a deleted memory takes its links")
    #expect(try store.entities.entity(id: house.id) != nil, "and leaves the entity")
    try store.entities.delete(house.id)
    #expect(try store.entities.links(of: detail.id).isEmpty)
}

@Test func domainTagsAreFreeText() throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    try store.tags.tag(.memory, "m1", "home")
    try store.tags.tag(.memory, "m1", "Home ")
    try store.tags.tag(.entity, "e1", "the old neighbourhood")
    try store.tags.tag(.entity, "e2", "HOME")
    #expect(try store.tags.tags(of: .memory, "m1") == ["home"])
    #expect(try store.tags.all() == ["HOME", "the old neighbourhood"] || store.tags.all() == ["home", "the old neighbourhood"])
    #expect(try store.tags.elements(.entity, tagged: "home") == ["e2"])
    try store.tags.untag(.memory, "m1", "HOME")
    #expect(try store.tags.tags(of: .memory, "m1").isEmpty)
}
