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
