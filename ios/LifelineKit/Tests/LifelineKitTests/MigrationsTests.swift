import Testing
import GRDB
@testable import LifelineKit

@Test func v1CreatesAllTables() throws {
    let db = try AppDatabase.inMemory()
    let names = try db.writer.read {
        try String.fetchAll($0, sql: "select name from sqlite_master where type='table' order by name")
    }
    #expect(Set(names).isSuperset(of: ["session", "segment", "word", "profile", "person"]))
}

@Test func foreignKeysAreEnforced() throws {
    let db = try AppDatabase.inMemory()
    let orphan = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "x", status: .pending)
    #expect(throws: DatabaseError.self) {
        try db.writer.write { try orphan.insert($0) }
    }
}

@Test func v2CreatesTheConfirmationTables() throws {
    let db = try AppDatabase.inMemory()
    let tables = try db.writer.read { try String.fetchAll($0, sql: "select name from sqlite_master where type = 'table' order by name") }
    for t in ["alias", "anchor", "candidate", "memory", "memory_person", "memory_place", "memory_span", "mention", "place"] {
        #expect(tables.contains(t), "missing \(t)")
    }
}

@Test func privateBecomesHiddenAndOldSessionsAreLanded() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v4")
    try queue.write { db in
        try db.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 0)")
        try db.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s2', '2026-10-02', NULL, 'b.m4a', '[]', 0)")
        try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'private', '2026-10-01')")
        try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_at) values ('m2', 'B', 'b', 'timeline', '2026-10-01')")
    }
    try Migrations.migrator.migrate(queue)
    let (hidden, excluded, landed, kinds) = try queue.read { db in
        (try Bool.fetchAll(db, sql: "select hidden_from_timeline from memory order by id"),
         try Bool.fetchAll(db, sql: "select excluded_from_ai from memory order by id"),
         try Bool.fetchAll(db, sql: "select landing_choice_made from session order by id"),
         try String.fetchAll(db, sql: "select kind from session order by id"))
    }
    #expect(hidden == [true, false] && excluded == [false, false])
    #expect(landed == [true, false], "a session that ended before M4 never gets a surprise landing; a crashed one still resumes")
    #expect(kinds == ["quick", "quick"])
}

@Test func v7AddsEmbeddingsAndSpanColumns() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v6")
    try queue.write { db in
        try db.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1)")
        try db.execute(sql: "insert into segment (id, session_id, \"index\", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 1000, 'hi', 'extracted')")
        try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01')")
        try db.execute(sql: "insert into memory_span (memory_id, segment_id, start_ms, end_ms, \"order\") values ('m1', 'g1', 0, 500, 0)")
    }
    try Migrations.migrator.migrate(queue)
    let (embeddingColumns, spanColumns) = try queue.read { db in
        (try db.columns(in: "memory_embedding").map(\.name), try db.columns(in: "memory_span").map(\.name))
    }
    #expect(Set(embeddingColumns) == ["memory_id", "model", "dims", "vector"])
    #expect(spanColumns.contains("title_text") && spanColumns.contains("candidate_id"))
    let (title, candidate) = try queue.read { db in
        (try String?.fetchOne(db, sql: "select title_text from memory_span where memory_id = 'm1'") ?? nil,
         try String?.fetchOne(db, sql: "select candidate_id from memory_span where memory_id = 'm1'") ?? nil)
    }
    #expect(title == nil && candidate == nil)
    try queue.write { db in
        try db.execute(sql: "insert into memory_embedding (memory_id, model, dims, vector) values ('m1', 'fake', 1, x'0000803f')")
        try db.execute(sql: "delete from memory where id = 'm1'")
    }
    #expect(try queue.read { try Int.fetchOne($0, sql: "select count(*) from memory_embedding") } == 0, "the embedding row goes with its memory")
}

@Test func v8AddsStoriesPairsAndContinuation() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v7")
    try queue.write { db in
        try db.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1)")
        try db.execute(sql: "insert into segment (id, session_id, \"index\", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 1000, 'hi', 'extracted')")
        try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01')")
        try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_at) values ('m2', 'B', 'b', 'timeline', '2026-10-01')")
        try db.execute(sql: "insert into memory_span (memory_id, segment_id, start_ms, end_ms, \"order\") values ('m1', 'g1', 0, 500, 0)")
    }
    try Migrations.migrator.migrate(queue)
    let tables = try queue.read { try String.fetchAll($0, sql: "select name from sqlite_master where type = 'table'") }
    for t in ["story", "story_moment", "duplicate_pair"] { #expect(tables.contains(t), "missing \(t)") }
    let continues = try queue.read { try Int?.fetchOne($0, sql: "select continues_order from memory_span where memory_id = 'm1'") ?? nil }
    #expect(continues == nil)
    try queue.write { db in
        try db.execute(sql: "insert into story (id, title, created_at) values ('st1', null, '2026-10-01')")
        try db.execute(sql: "insert into story (id, title, created_at) values ('st2', 'Two', '2026-10-01')")
        try db.execute(sql: "insert into story_moment (story_id, memory_id, \"order\") values ('st1', 'm1', 0)")
    }
    #expect(throws: DatabaseError.self, "one story per memory") {
        try queue.write { try $0.execute(sql: "insert into story_moment (story_id, memory_id, \"order\") values ('st2', 'm1', 0)") }
    }
    try queue.write { db in
        try db.execute(sql: "insert into duplicate_pair (id, a_memory_id, b_memory_id, score, verdict, status) values ('p1', 'm1', 'm2', 0.9, 'same_moment', 'open')")
        try db.execute(sql: "delete from memory where id = 'm2'")
    }
    #expect(try queue.read { try Int.fetchOne($0, sql: "select count(*) from duplicate_pair") } == 0, "the pair goes with its memory")
}

@Test func schemaVersionsOrderByMigrationPosition() {
    #expect(Migrations.currentSchemaVersion == "v14")
    #expect(Migrations.isNewer("v9", than: "v8") && !Migrations.isNewer("v8", than: "v9") && Migrations.isNewer("v10", than: "v9"))
    #expect(Migrations.isNewer("v8", than: "v7") && !Migrations.isNewer("v7", than: "v8") && !Migrations.isNewer("v8", than: "v8"))
    #expect(Migrations.isNewer("v99", than: "v8"), "an unknown version is from the future")
}

@Test func v11OnAPopulatedV10Database() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v10")
    try queue.write { db in
        try db.execute(sql: """
            insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1);
            insert into segment (id, session_id, "index", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 1000, 'hi', 'extracted');
            insert into entity (id, type, title, created_at) values ('e1', 'person', 'Maya', '2026-10-01');
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01');
            """)
    }
    try Migrations.migrator.migrate(queue)
    let (columns, kept) = try queue.read { db in
        (try db.columns(in: "interviewer_turn").map(\.name),
         try Int.fetchOne(db, sql: "select count(*) from memory") ?? 0)
    }
    #expect(Set(columns) == ["id", "session_id", "kind", "source", "text", "start_ms", "end_ms", "interrupted"])
    #expect(kept == 1, "the existing archive is untouched")
    try queue.write { db in
        try db.execute(sql: "insert into interviewer_turn (id, session_id, kind, source, text, start_ms) values ('t1', 's1', 'opening', 'fixed', 'Hello.', 0)")
    }
    #expect(throws: DatabaseError.self, "a turn needs its session") {
        try queue.write { try $0.execute(sql: "insert into interviewer_turn (id, session_id, kind, source, text, start_ms) values ('t2', 'nope', 'opening', 'fixed', 'Hello.', 0)") }
    }
    try queue.write { try $0.execute(sql: "delete from session where id = 's1'") }
    #expect(try queue.read { try Int.fetchOne($0, sql: "select count(*) from interviewer_turn") } == 0, "the turn goes with its session")
}

@Test func v12AddsSubjectAndOriginAndOldSessionsReadAsTab() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v11")
    try queue.write { db in
        try db.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1)")
    }
    try Migrations.migrator.migrate(queue)
    let session = try #require(try queue.read { try Session.fetchOne($0, sql: "select * from session where id = 's1'") })
    #expect(session.subjectEntityID == nil)
    #expect(session.startedFrom == .tab)
}

@Test func v13OnAPopulatedV12Database() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v12")
    try queue.write { db in
        try db.execute(sql: """
            insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1);
            insert into segment (id, session_id, "index", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 1000, 'hi', 'extracted');
            insert into entity (id, type, title, created_at) values ('e1', 'person', 'Maya', '2026-10-01');
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01');
            insert into moment_entity (memory_id, entity_id, relation) values ('m1', 'e1', 'mention');
            """)
    }
    let tables = ["session", "segment", "entity", "memory", "moment_entity"]
    func rows() throws -> [[Row]] {
        try queue.read { db in try tables.map { try Row.fetchAll(db, sql: "select * from \($0) order by rowid") } }
    }
    let rowsBefore = try rows()
    try Migrations.migrator.migrate(queue, upTo: "v13")  // v14 adds columns to two of these tables; it has its own test.
    #expect(try rows() == rowsBefore, "no existing row or column changes")
    #expect(Set(try queue.read { try $0.columns(in: "photo") }.map(\.name))
            == ["id", "file_name", "asset_local_id", "taken_at", "taken_origin", "lat", "lon", "location_origin", "sha256", "pixel_width", "pixel_height", "added_at"])
    func photo(_ id: String) -> String {
        "insert into photo (id, file_name, sha256, pixel_width, pixel_height, added_at) values ('\(id)', '\(id).jpg', '\(id)-hash', 4, 3, '2026-10-01')"
    }
    try queue.write { db in
        try db.execute(sql: photo("p1"))
        try db.execute(sql: "insert into photo_link (photo_id, entity_id, role, sort_order) values ('p1', 'e1', 'cover', 0)")
    }
    // p2 has no link yet, so only the check can refuse these two.
    try queue.write { try $0.execute(sql: photo("p2")) }
    #expect(throws: DatabaseError.self, "a link names one subject") {
        try queue.write { try $0.execute(sql: "insert into photo_link (photo_id, entity_id, memory_id, role, sort_order) values ('p2', 'e1', 'm1', 'attached', 1)") }
    }
    #expect(throws: DatabaseError.self, "a link names a subject") {
        try queue.write { try $0.execute(sql: "insert into photo_link (photo_id, role, sort_order) values ('p2', 'attached', 1)") }
    }
    #expect(throws: DatabaseError.self, "one cover per subject") {
        try queue.write { try $0.execute(sql: "insert into photo_link (photo_id, entity_id, role, sort_order) values ('p2', 'e1', 'cover', 1)") }
    }
    try queue.write { try $0.execute(sql: "delete from entity where id = 'e1'") }
    #expect(try queue.read { try Int.fetchOne($0, sql: "select count(*) from photo_link") } == 0, "the link goes with its entity")
    #expect(try queue.read { try Int.fetchOne($0, sql: "select count(*) from photo") } == 2, "the photo row waits for the sweep")
}

@Test func v14KeepsEveryRowAndAddsNothingToOldLinks() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v13")
    try queue.write { db in
        try db.execute(sql: """
            insert into entity (id, type, title, created_at) values ('e1', 'person', 'Maya', '2026-10-01');
            insert into person (id, entity_id, display_name, is_owner) values ('e1', 'e1', '', 0);
            insert into memory (id, title, summary_quote, visibility, created_at) values ('m1', 'A', 'a', 'timeline', '2026-10-01');
            insert into moment_entity (memory_id, entity_id, relation, role_text) values ('m1', 'e1', 'mention', 'my sister');
            """)
    }
    let tables = ["entity", "person", "memory", "moment_entity"]
    func rows() throws -> [[Row]] {
        try queue.read { db in try tables.map { try Row.fetchAll(db, sql: "select * from \($0) order by rowid") } }
    }
    let before = try rows()
    try Migrations.migrator.migrate(queue)
    let after = try rows()
    for (old, new) in zip(before, after) {
        #expect(old.count == new.count, "no row is added or deleted")
        for (o, n) in zip(old, new) { for (column, value) in o { #expect(n[column] == value, "\(column) is unchanged") } }
    }
    try queue.read { db in
        #expect(try Row.fetchOne(db, sql: "select origin from moment_entity")?["origin"] as String? == nil, "an old link has no origin")
        #expect(try Row.fetchOne(db, sql: "select person_handle from moment_entity")?["person_handle"] as String? == nil)
        #expect(try Bool.fetchOne(db, sql: "select created_by_guess from person") == false)
        #expect(try Row.fetchOne(db, sql: "select contact_identifier from person")?["contact_identifier"] as String? == nil)
        let tableNames = try String.fetchAll(db, sql: "select name from sqlite_master where type = 'table'")
        #expect(tableNames.contains("contact_declined") && tableNames.contains("candidate_person_choice"))
    }
}

@Test func oneContactBelongsToOnePerson() throws {
    let db = try AppDatabase.inMemory()
    func person(_ id: String) -> String {
        """
        insert into entity (id, type, title, created_at) values ('\(id)', 'person', '\(id)', '2026-10-01');
        insert into person (id, entity_id, display_name, is_owner) values ('\(id)', '\(id)', '', 0);
        """
    }
    try db.writer.write { try $0.execute(sql: person("a") + person("b") + person("c")) }
    // Persons with no contact do not collide.
    try db.writer.write { try $0.execute(sql: "update person set contact_identifier = null") }
    try db.writer.write { try $0.execute(sql: "update person set contact_identifier = 'k1' where id = 'a'") }
    #expect(throws: DatabaseError.self, "a second person cannot take the same contact") {
        try db.writer.write { try $0.execute(sql: "update person set contact_identifier = 'k1' where id = 'b'") }
    }
}

@Test func contactDeclinedAndCandidateChoiceFollowTheirOwners() throws {
    let db = try AppDatabase.inMemory()
    try db.writer.write { db in
        try db.execute(sql: """
            insert into entity (id, type, title, created_at) values ('p1', 'person', 'Maya', '2026-10-01');
            insert into person (id, entity_id, display_name, is_owner) values ('p1', 'p1', '', 0);
            insert into contact_declined (person_id, contact_identifier) values ('p1', 'k1');
            """)
    }
    #expect(throws: DatabaseError.self, "the pair is the key") {
        try db.writer.write { try $0.execute(sql: "insert into contact_declined (person_id, contact_identifier) values ('p1', 'k1')") }
    }
    try db.writer.write { try $0.execute(sql: "delete from person where id = 'p1'") }
    #expect(try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from contact_declined") } == 0, "declined goes with the person")
}

@Test func aCandidateChoiceIsOnePerSaidNameAndGoesWithItsCandidate() throws {
    let db = try AppDatabase.inMemory()
    try db.writer.write { db in
        try db.execute(sql: """
            insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1);
            insert into segment (id, session_id, "index", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 1000, 'hi', 'extracted');
            """)
    }
    let candidateColumns = try db.writer.read { try $0.columns(in: "candidate") }.map(\.name)
    #expect(candidateColumns.contains("id"))
    // Build the minimal candidate row from its own NOT NULL columns.
    let required = try db.writer.read { try $0.columns(in: "candidate") }.filter { $0.isNotNull && $0.defaultValueSQL == nil }.map(\.name)
    let values = required.map { name -> String in
        switch name {
        case "id": "'c1'"
        case "session_id": "'s1'"
        case "segment_id": "'g1'"
        case "created_at": "'2026-10-01'"
        default: "'x'"
        }
    }
    try db.writer.write { db in
        try db.execute(sql: "insert into candidate (\(required.joined(separator: ", "))) values (\(values.joined(separator: ", ")))")
        try db.execute(sql: "insert into candidate_person_choice (candidate_id, said_name, choice) values ('c1', 'maya', 'new')")
    }
    #expect(throws: DatabaseError.self, "one answer for a said name on a card") {
        try db.writer.write { try $0.execute(sql: "insert into candidate_person_choice (candidate_id, said_name, choice) values ('c1', 'maya', 'not_a_person')") }
    }
    try db.writer.write { try $0.execute(sql: "delete from candidate where id = 'c1'") }
    #expect(try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from candidate_person_choice") } == 0)
}
