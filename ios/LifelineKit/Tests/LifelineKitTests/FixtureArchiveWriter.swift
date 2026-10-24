import Foundation
import Testing
import GRDB
@testable import LifelineKit

/// Writes the UI tests' restore fixtures when asked (`LIFELINE_WRITE_FIXTURES=<dir>`); a no-op
/// otherwise. Run once and commit the files; they are tiny and invented.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LIFELINE_WRITE_FIXTURES"] != nil))
func writeRestoreFixtureArchives() throws {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LIFELINE_WRITE_FIXTURES"]!)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    // v8: one kept memory, "The orange house", with its audio.
    let root = FileManager.default.temporaryDirectory.appending(path: "fixture-v8-\(UUID().uuidString)")
    let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
    let store = ExtractionStore(db)
    let (id, segs) = try StoreFixtures.session(in: store.sessions, segments: ["we lived in an orange house"])
    try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segs[0].id, title: "The orange house")
    try Data(repeating: 7, count: 2_000).write(to: AudioLocation.url(for: id, under: root))
    try Backup.export(root: root, appVersion: "fixture", to: out.appending(path: "fixture-v8.lifeline"), database: db)

    // v7: one session and memory from before M5, and its audio file missing.
    let old = FileManager.default.temporaryDirectory.appending(path: "fixture-v7-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: old.appending(path: "Lifeline/audio"), withIntermediateDirectories: true)
    var config = Configuration(); config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(path: old.appending(path: "Lifeline/lifeline.sqlite").path, configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v7")
    try queue.write { db in
        try db.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-09-01', '2026-09-01', 's1.m4a', '[]', 1)")
        try db.execute(sql: "insert into segment (id, session_id, \"index\", start_ms, end_ms, text, status) values ('g1', 's1', 0, 0, 2000, 'the canal behind the house', 'extracted')")
        try db.execute(sql: "insert into candidate (id, segment_id, extractor_version, ordinal, kind, payload, confidence, status, created_at) values ('c1', 'g1', 'v4', 0, 'memory', '{\"ref\":\"m1\",\"title\":\"The canal\",\"quote\":\"the canal behind the house\",\"segment_span\":{\"start_word\":0,\"end_word\":4},\"people_refs\":[],\"place_text\":null,\"anchors\":[],\"same_as_memory_id\":null,\"collection_hint\":null,\"chapter_hint\":null,\"confidence\":0.9}', 0.9, 'accepted', '2026-09-01')")
        try db.execute(sql: "insert into memory (id, title, summary_quote, visibility, created_from_candidate_id, created_at) values ('m1', 'The canal', 'the canal behind the house', 'timeline', 'c1', '2026-09-01')")
        try db.execute(sql: "insert into memory_span (memory_id, segment_id, start_ms, end_ms, \"order\") values ('m1', 'g1', 0, 2000, 0)")
    }
    try Backup.export(root: old, appVersion: "fixture", to: out.appending(path: "fixture-v7-missing-audio.lifeline"))
}
