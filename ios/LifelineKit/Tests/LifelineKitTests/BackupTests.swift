import Foundation
import Testing
import GRDB
@testable import LifelineKit

/// A root the way the app lays it out: <root>/Lifeline/lifeline.sqlite, audio/, pauses.log.
private struct Root {
    let url: URL
    let db: AppDatabase
    let store: ExtractionStore

    init(sessions: Int = 2, memories: Int = 3) throws {
        url = FileManager.default.temporaryDirectory.appending(path: "lifeline-backup-\(UUID().uuidString)")
        db = try AppDatabase.open(at: url.appending(path: "Lifeline/lifeline.sqlite"))
        store = ExtractionStore(db)
        // Memories are spread over the sessions, one per segment (a card's ordinal is unique per segment).
        var made = 0
        for i in 0..<sessions {
            let share = (memories - made) / (sessions - i) + ((memories - made) % (sessions - i) > 0 ? 1 : 0)
            let texts = (0..<max(1, share)).map { "the garden had a pomegranate tree \(i) \($0)" }
            let (id, segs) = try StoreFixtures.session(in: store.sessions, segments: texts)
            try Data(repeating: UInt8(i + 1), count: 1_000 * (i + 1)).write(to: AudioLocation.url(for: id, under: url))
            for seg in segs where made < memories {
                try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: seg.id, title: "Memory \(made)")
                made += 1
            }
        }
        try "paused once\n".write(to: url.appending(path: "Lifeline/pauses.log"), atomically: true, encoding: .utf8)
    }

    func audioBytes() throws -> [String: Data] {
        let dir = try AudioLocation.directory(under: url)
        return Dictionary(uniqueKeysWithValues: try FileManager.default.contentsOfDirectory(atPath: dir.path).map { ($0, try Data(contentsOf: dir.appending(path: $0))) })
    }
}

@Test func exportRoundTripsEverything() throws {
    let source = try Root(sessions: 2, memories: 3)
    let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
    let archive = source.url.appending(path: Backup.defaultFileName(now: noon))
    #expect(archive.lastPathComponent == "Lifeline-2026-10-24.lifeline")
    let manifest = try Backup.export(root: source.url, appVersion: "1.0 (7)", to: archive, database: source.db)
    #expect(manifest.sessions == 2 && manifest.memories == 3 && manifest.audioFiles == 2 && manifest.audioBytes == 3_000)
    #expect(manifest.schemaVersion == Migrations.currentSchemaVersion && manifest.appVersion == "1.0 (7)")
    #expect(try Backup.inspect(archive) == manifest)

    let target = FileManager.default.temporaryDirectory.appending(path: "lifeline-restore-\(UUID().uuidString)")
    _ = try AppDatabase.open(at: target.appending(path: "Lifeline/lifeline.sqlite"))   // a phone with its own, empty archive
    let pending = try Backup.stage(archive, root: target, appVersion: "1.0 (7)")
    #expect(pending.manifest == manifest && FileManager.default.fileExists(atPath: pending.safetyCopy.path))
    #expect(try Backup.applyPendingRestore(root: target))
    let restored = ExtractionStore(try AppDatabase.open(at: target.appending(path: "Lifeline/lifeline.sqlite")))
    #expect(try restored.sessions.listSessions().count == 2 && (try restored.memories.allMemories()).count == 3)
    let bytes = try source.audioBytes()
    let restoredDir = try AudioLocation.directory(under: target)
    for (name, data) in bytes { #expect(try Data(contentsOf: restoredDir.appending(path: name)) == data) }
    #expect(try String(contentsOf: target.appending(path: "Lifeline/pauses.log"), encoding: .utf8) == "paused once\n")
    #expect(!FileManager.default.fileExists(atPath: target.appending(path: "Lifeline-restore-pending.json").path))
    #expect(try !Backup.applyPendingRestore(root: target), "nothing left to apply")
}

@Test func exportedDatabaseMatchesTheSourceUnderConcurrentWrites() async throws {
    let source = try Root(sessions: 1, memories: 1)
    let before = try source.store.sessions.listSessions().count
    let writer = Task.detached { [sessions = source.store.sessions] in
        for _ in 0..<40 { _ = try? StoreFixtures.session(in: sessions, segments: ["more"]) }
    }
    let archive = source.url.appending(path: "during.lifeline")
    _ = try Backup.export(root: source.url, appVersion: "1.0", to: archive, database: source.db)
    await writer.value
    let after = try source.store.sessions.listSessions().count
    let staging = FileManager.default.temporaryDirectory.appending(path: "lifeline-check-\(UUID().uuidString)")
    _ = try AppDatabase.open(at: staging.appending(path: "Lifeline/lifeline.sqlite"))
    _ = try Backup.stage(archive, root: staging, appVersion: "1.0")
    #expect(try Backup.applyPendingRestore(root: staging))
    let copy = try AppDatabase.open(at: staging.appending(path: "Lifeline/lifeline.sqlite"))
    let count = try SessionRepository(copy).listSessions().count
    #expect(count >= before && count <= after)
    #expect(try integrity(copy) == "ok")
}

private func integrity(_ db: AppDatabase) throws -> String? {
    try db.writer.read { try String.fetchOne($0, sql: "pragma integrity_check") }
}

@Test func newerSchemaIsRefusedOlderIsMigrated() throws {
    let source = try Root(sessions: 1, memories: 1)
    let archive = source.url.appending(path: "a.lifeline")
    _ = try Backup.export(root: source.url, appVersion: "1.0", to: archive, database: source.db)
    // Rewrite the manifest to claim a schema from the future.
    let future = try Backup.rewritingManifest(of: archive) { $0.schemaVersion = "v99" }
    let target = FileManager.default.temporaryDirectory.appending(path: "lifeline-t-\(UUID().uuidString)")
    _ = try AppDatabase.open(at: target.appending(path: "Lifeline/lifeline.sqlite"))
    #expect(throws: Backup.Error.newerSchema("v99")) { try Backup.stage(future, root: target, appVersion: "1.0") }

    // An archive from a v7 database restores and migrates on open.
    let oldRoot = FileManager.default.temporaryDirectory.appending(path: "lifeline-v7-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: oldRoot.appending(path: "Lifeline"), withIntermediateDirectories: true)
    var config = Configuration(); config.foreignKeysEnabled = true
    let queue = try DatabaseQueue(path: oldRoot.appending(path: "Lifeline/lifeline.sqlite").path, configuration: config)
    try Migrations.migrator.migrate(queue, upTo: "v7")
    try queue.write { try $0.execute(sql: "insert into session (id, started_at, ended_at, audio_path, stage_log, landing_choice_made) values ('s1', '2026-10-01', '2026-10-01', 'a.m4a', '[]', 1)") }
    let oldArchive = oldRoot.appending(path: "old.lifeline")
    let old = try Backup.export(root: oldRoot, appVersion: "0.9", to: oldArchive)
    #expect(old.schemaVersion == "v7" && old.sessions == 1)
    _ = try Backup.stage(oldArchive, root: target, appVersion: "1.0")
    #expect(try Backup.applyPendingRestore(root: target))
    let opened = try AppDatabase.open(at: target.appending(path: "Lifeline/lifeline.sqlite"))
    #expect(try SessionRepository(opened).listSessions().count == 1)
    #expect(try opened.writer.read { try $0.tableExists("story") }, "migrated to the current schema on open")
}

@Test func applyPendingRestoreIsIdempotentAndSkipsAnIncompleteStage() throws {
    let target = try Root(sessions: 1, memories: 1)
    let staging = target.url.appending(path: "Lifeline-restore-staging")
    try FileManager.default.createDirectory(at: staging.appending(path: "audio"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: target.url.appending(path: "Lifeline-restore-pending.json"))
    #expect(try !Backup.applyPendingRestore(root: target.url), "no lifeline.sqlite in the stage: discarded")
    #expect(!FileManager.default.fileExists(atPath: staging.path) && !FileManager.default.fileExists(atPath: target.url.appending(path: "Lifeline-restore-pending.json").path))
    #expect(try target.store.sessions.listSessions().count == 1, "the original is intact")
}

@Test func theKeyIsNeverInTheArchive() throws {
    let source = try Root(sessions: 1, memories: 1)
    let archive = source.url.appending(path: "a.lifeline")
    _ = try Backup.export(root: source.url, appVersion: "1.0", to: archive, database: source.db)
    let entries = try Backup.entryNames(of: archive)
    let audio = entries.filter { $0.hasPrefix("audio/") }
    #expect(Set(entries.filter { !$0.hasPrefix("audio/") }) == ["lifeline.sqlite", "pauses.log", "manifest.json"])
    #expect(audio.count == 1 && audio.allSatisfy { $0.hasSuffix(".m4a") })
}

// MARK: - Review fixes

private func docs() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "lifeline-docs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func archives(in dir: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lifeline" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

@Test func applyKeepsWhatWasWrittenAfterStaging() throws {
    let phone = try Root(sessions: 1, memories: 1)
    let other = try Root(sessions: 2, memories: 2)
    let archive = other.url.appending(path: "other.lifeline")
    _ = try Backup.export(root: other.url, appVersion: "1.0", to: archive, database: other.db)
    let documents = try docs()
    _ = try Backup.stage(archive, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    // The person keeps using the app before closing it: one more recording.
    _ = try StoreFixtures.session(in: phone.store.sessions, segments: ["told after Replace was tapped"])
    #expect(try Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: documents))
    let copies = try archives(in: documents)
    #expect(copies.count == 2, "the stage-time copy and the launch-time copy of what the phone held: \(copies.map(\.lastPathComponent))")
    let late = try copies.map { try Backup.inspect($0) }.max { $0.sessions < $1.sessions }
    #expect(late?.sessions == 2, "the recording made after Replace is in the launch-time copy")
    let restored = ExtractionStore(try AppDatabase.open(at: phone.url.appending(path: "Lifeline/lifeline.sqlite")))
    #expect(try restored.sessions.listSessions().count == 2 && (try restored.memories.allMemories()).count == 2)
    #expect(!FileManager.default.fileExists(atPath: phone.url.appending(path: "Lifeline-replaced").path), "the replaced archive is zipped into Documents, then gone")
}

@Test func safetyCopiesNeverOverwrite() throws {
    let phone = try Root(sessions: 1, memories: 1)
    let archive = phone.url.appending(path: "self.lifeline")
    _ = try Backup.export(root: phone.url, appVersion: "1.0", to: archive, database: phone.db)
    let documents = try docs()
    let first = try Backup.stage(archive, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    let second = try Backup.stage(archive, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    let made = try archives(in: documents)
    #expect(first.safetyCopy != second.safetyCopy && made.count == 2)
    #expect(first.safetyCopy.lastPathComponent.hasPrefix("Lifeline-before-restore-"))
}

@Test func applyRecoversFromAHalfSwap() throws {
    let phone = try Root(sessions: 1, memories: 1)
    let other = try Root(sessions: 3, memories: 1)
    let archive = other.url.appending(path: "other.lifeline")
    _ = try Backup.export(root: other.url, appVersion: "1.0", to: archive, database: other.db)
    let documents = try docs()
    _ = try Backup.stage(archive, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    // A crash after the old archive was moved aside and before the stage moved in.
    let fm = FileManager.default
    try fm.moveItem(at: phone.url.appending(path: "Lifeline"), to: phone.url.appending(path: "Lifeline-replaced"))
    #expect(try Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: documents))
    let restored = ExtractionStore(try AppDatabase.open(at: phone.url.appending(path: "Lifeline/lifeline.sqlite")))
    #expect(try restored.sessions.listSessions().count == 3)
    #expect(try archives(in: documents).count == 2, "the moved-aside archive was still saved to Documents")
    #expect(!fm.fileExists(atPath: phone.url.appending(path: "Lifeline-replaced").path))
    // A crash after the stage moved in and before the marker went: the next launch only tidies.
    try Data("{}".utf8).write(to: phone.url.appending(path: "Lifeline-restore-pending.json"))
    #expect(try !Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: documents))
    #expect(try ExtractionStore(try AppDatabase.open(at: phone.url.appending(path: "Lifeline/lifeline.sqlite"))).sessions.listSessions().count == 3)
}

@Test func exportThroughASecondConnectionIsConsistentWhileTheAppWrites() async throws {
    let source = try Root(sessions: 1, memories: 1)
    let started = LogCollector(), stop = LogCollector()
    let writer = Task.detached { [sessions = source.store.sessions] in
        var n = 0
        while stop.all.isEmpty && n < 2_000 { _ = try? StoreFixtures.session(in: sessions, segments: ["more"]); n += 1; if n == 3 { started.append("go") } }
        return n
    }
    while started.all.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    let archive = source.url.appending(path: "during.lifeline")
    _ = try Backup.export(root: source.url, appVersion: "1.0", to: archive, database: nil)   // the app's own path: no shared connection
    #expect(stop.all.isEmpty && !writer.isCancelled, "the writer was still going when the export finished")
    stop.append("stop")
    let total = await writer.value
    let staging = FileManager.default.temporaryDirectory.appending(path: "lifeline-check-\(UUID().uuidString)")
    _ = try AppDatabase.open(at: staging.appending(path: "Lifeline/lifeline.sqlite"))
    _ = try Backup.stage(archive, root: staging, appVersion: "1.0", safetyCopyDirectory: try docs())
    #expect(try Backup.applyPendingRestore(root: staging, safetyCopyDirectory: try docs()))
    let copy = try AppDatabase.open(at: staging.appending(path: "Lifeline/lifeline.sqlite"))
    let count = try SessionRepository(copy).listSessions().count
    #expect(count >= 4 && count <= total + 1)
    #expect(try integrity(copy) == "ok")
}

@Test func applyOpensTheAppEvenWhenTheReplacedCopyCannotBeWritten() throws {
    let phone = try Root(sessions: 1, memories: 1)
    let other = try Root(sessions: 2, memories: 1)
    let archive = other.url.appending(path: "other.lifeline")
    _ = try Backup.export(root: other.url, appVersion: "1.0", to: archive, database: other.db)
    let documents = try docs()
    _ = try Backup.stage(archive, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    // Documents cannot take the copy (a file sits where the directory should be): the restore still applies.
    let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
    try Data("x".utf8).write(to: blocked)
    #expect(try Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: blocked))
    #expect(try ExtractionStore(try AppDatabase.open(at: phone.url.appending(path: "Lifeline/lifeline.sqlite"))).sessions.listSessions().count == 2)
    #expect(FileManager.default.fileExists(atPath: phone.url.appending(path: "Lifeline-replaced/lifeline.sqlite").path), "the old archive waits for a launch that can save it")
    // The next launch, with room: the old archive is saved and the folder goes.
    #expect(try !Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: documents))
    #expect(try archives(in: documents).count == 2 && !FileManager.default.fileExists(atPath: phone.url.appending(path: "Lifeline-replaced").path))
}

@Test func aSecondRestoreOpensTheAppWhenTheFirstReplacedCopyIsStillWaiting() throws {
    let phone = try Root(sessions: 1, memories: 1)
    let documents = try docs()
    let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
    try Data("x".utf8).write(to: blocked)
    // Two restores in a row on a phone too full to save the replaced archive.
    for sessions in [2, 3] {
        let other = try Root(sessions: sessions, memories: 1)
        let archive = other.url.appending(path: "other.lifeline")
        _ = try Backup.export(root: other.url, appVersion: "1.0", to: archive, database: other.db)
        let current = try AppDatabase.open(at: phone.url.appending(path: "Lifeline/lifeline.sqlite"))
        _ = try Backup.stage(archive, root: phone.url, appVersion: "1.0", database: current, safetyCopyDirectory: documents)
        #expect(try Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: blocked), "the app opens, restore \(sessions)")
    }
    #expect(try ExtractionStore(try AppDatabase.open(at: phone.url.appending(path: "Lifeline/lifeline.sqlite"))).sessions.listSessions().count == 3)
    let fm = FileManager.default
    let aside = try fm.contentsOfDirectory(atPath: phone.url.path).filter { $0.hasPrefix("Lifeline-replaced") }
    #expect(aside.count == 2, "both replaced archives wait on the phone")
    #expect(!fm.fileExists(atPath: phone.url.appending(path: "Lifeline-restore-pending.json").path))
    // The next launch with room saves both and removes both folders.
    #expect(try !Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: documents))
    #expect(try fm.contentsOfDirectory(atPath: phone.url.path).filter { $0.hasPrefix("Lifeline-replaced") }.isEmpty)
    #expect(try archives(in: documents).count == 4, "two safety copies from staging, two replaced archives")
}

@Test func aFailedSecondStageLeavesNoRestorePending() throws {
    let phone = try Root(sessions: 1, memories: 1)
    let documents = try docs()
    let first = try Root(sessions: 2, memories: 1), second = try Root(sessions: 3, memories: 1)
    let a = first.url.appending(path: "a.lifeline"), b = second.url.appending(path: "b.lifeline")
    _ = try Backup.export(root: first.url, appVersion: "1.0", to: a, database: first.db)
    _ = try Backup.export(root: second.url, appVersion: "1.0", to: b, database: second.db)
    _ = try Backup.stage(a, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    // The person picks another copy before relaunching, and that stage fails after the unzip.
    let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
    try Data("x".utf8).write(to: blocked)
    #expect(throws: (any Error).self) {
        try Backup.stage(b, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: blocked)
    }
    let fm = FileManager.default
    #expect(!fm.fileExists(atPath: phone.url.appending(path: "Lifeline-restore-pending.json").path), "no marker points at the failed copy")
    #expect(try !Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: documents), "the next launch applies nothing")
    #expect(try phone.store.sessions.listSessions().count == 1, "the phone keeps its own archive")
}

@Test func launchRemovesExportsLeftInTheTemporaryFolder() throws {
    let tmp = try docs()
    for name in ["Lifeline-2026-10-24.lifeline", "Lifeline-2026-10-23.lifeline", "restore-1.lifeline", "notes.txt"] {
        try Data("x".utf8).write(to: tmp.appending(path: name))
    }
    #expect(Backup.removeTemporaryExports(in: tmp) == 2)
    #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).sorted() == ["notes.txt", "restore-1.lifeline"], "only the app's export files go")
}

@Test func copiesWrittenToDocumentsStayOutOfCloudBackup() throws {
    let phone = try Root(sessions: 1, memories: 1)
    let archive = phone.url.appending(path: "self.lifeline")
    _ = try Backup.export(root: phone.url, appVersion: "1.0", to: archive, database: phone.db)
    let documents = try docs()
    let pending = try Backup.stage(archive, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    #expect(try pending.safetyCopy.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "the safety copy never rides the phone's cloud backup")
    #expect(try Backup.applyPendingRestore(root: phone.url, safetyCopyDirectory: documents))
    for copy in try archives(in: documents) {
        #expect(try copy.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, Comment(rawValue: copy.lastPathComponent))
    }
    #expect(try archive.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "every archive the app writes")
}
