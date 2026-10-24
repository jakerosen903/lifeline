import Foundation
import GRDB
import ZIPFoundation

/// What a `.lifeline` file says about itself.
public struct BackupManifest: Codable, Sendable, Equatable {
    public var appVersion: String
    public var schemaVersion: String
    public var createdAt: Date
    public var sessions: Int
    public var memories: Int
    public var audioFiles: Int
    public var audioBytes: Int64

    public init(appVersion: String, schemaVersion: String, createdAt: Date, sessions: Int, memories: Int, audioFiles: Int, audioBytes: Int64) {
        self.appVersion = appVersion; self.schemaVersion = schemaVersion; self.createdAt = createdAt
        self.sessions = sessions; self.memories = memories; self.audioFiles = audioFiles; self.audioBytes = audioBytes
    }
}

/// One file that holds everything (M6): the database (checkpointed, copied through GRDB's backup
/// API so a live write cannot tear it), the audio, the pause log and a manifest. The API key is
/// never in it. A restore is staged, a safety copy of the phone's current archive is written
/// first, and the swap happens at the next launch before the database opens.
public enum Backup {
    public enum Error: Swift.Error, Equatable {
        case newerSchema(String)
        case notAnArchive
        case incomplete
    }

    static let databaseName = "lifeline.sqlite"
    static let manifestName = "manifest.json"
    static let pausesName = "pauses.log"
    static let audioDirectory = "audio"
    static let stagingName = "Lifeline-restore-staging"
    static let markerName = "Lifeline-restore-pending.json"
    static let replacedName = "Lifeline-replaced"

    public static func defaultFileName(now: Date = .now) -> String {
        "Lifeline-\(Self.day(now)).lifeline"
    }

    /// Where safety copies go: Documents, visible in Files.
    public static func safetyCopyDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    // MARK: - Export

    /// Writes the archive. `database` is the open database when the app has one (its connection
    /// does the consistent copy); otherwise the file is opened read-write for the copy.
    @discardableResult
    public static func export(root: URL, appVersion: String, to destination: URL, database: AppDatabase? = nil,
                              progress: @Sendable (String) -> Void = { _ in }) throws -> BackupManifest {
        try export(appDirectory: AudioLocation.rootDirectory(under: root), appVersion: appVersion, to: destination, database: database, progress: progress)
    }

    /// The archive is written beside `destination` under a temporary name and moved into place
    /// when complete, so a half-written file never looks like a copy.
    static func export(appDirectory appDir: URL, appVersion: String, to destination: URL, database: AppDatabase?,
                       progress: @Sendable (String) -> Void) throws -> BackupManifest {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "lifeline-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        progress("Copying your memories…")
        let dbCopy = work.appending(path: databaseName)
        let (sessions, memories) = try copyDatabase(from: appDir.appending(path: databaseName), to: dbCopy, database: database)

        var audioFiles = 0
        var audioBytes: Int64 = 0
        let audioDir = appDir.appending(path: audioDirectory)
        let audio = ((try? fm.contentsOfDirectory(atPath: audioDir.path)) ?? []).filter { $0.hasSuffix(".m4a") }.sorted()
        for name in audio {
            audioFiles += 1
            audioBytes += Int64((try? fm.attributesOfItem(atPath: audioDir.appending(path: name).path)[.size] as? Int) ?? 0)
        }
        // Whole seconds: the manifest round-trips through ISO 8601 and must compare equal after.
        let created = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        let manifest = BackupManifest(appVersion: appVersion, schemaVersion: try schemaVersion(of: dbCopy), createdAt: created,
                                      sessions: sessions, memories: memories, audioFiles: audioFiles, audioBytes: audioBytes)

        progress(audioFiles == 1 ? "Packing 1 recording…" : "Packing \(audioFiles) recordings…")
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).partial")
        try? fm.removeItem(at: partial)
        let archive = try Archive(url: partial, accessMode: .create)
        try archive.addEntry(with: databaseName, fileURL: dbCopy, compressionMethod: .deflate)
        for name in audio {
            try archive.addEntry(with: "\(audioDirectory)/\(name)", fileURL: audioDir.appending(path: name), compressionMethod: .none)
        }
        let pauses = appDir.appending(path: pausesName)
        if fm.fileExists(atPath: pauses.path) { try archive.addEntry(with: pausesName, fileURL: pauses, compressionMethod: .deflate) }
        let manifestData = try JSONEncoder.manifest.encode(manifest)
        try archive.addEntry(with: manifestName, type: .file, uncompressedSize: Int64(manifestData.count), compressionMethod: .deflate) { position, size in
            manifestData.subdata(in: Int(position)..<Int(position) + size)
        }
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: partial, to: destination)
        // The audio directory stays out of the phone's cloud backup on purpose; so does every copy of it.
        try AudioLocation.applyBackupExclusion(to: destination)
        return manifest
    }

    /// A name in `directory` that is not taken: `<stem>.lifeline`, then `<stem>-2.lifeline`, …
    static func freeName(in directory: URL, stem: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appending(path: "\(stem).lifeline")
        var n = 2
        while fm.fileExists(atPath: candidate.path) { candidate = directory.appending(path: "\(stem)-\(n).lifeline"); n += 1 }
        return candidate
    }

    /// The manifest, without unpacking anything else.
    public static func inspect(_ archive: URL) throws -> BackupManifest {
        guard let zip = try? Archive(url: archive, accessMode: .read), let entry = zip[manifestName] else { throw Error.notAnArchive }
        var data = Data()
        _ = try zip.extract(entry) { data.append($0) }
        do { return try JSONDecoder.manifest.decode(BackupManifest.self, from: data) } catch { throw Error.notAnArchive }
    }

    /// Entry names, for tests and for the Settings summary.
    public static func entryNames(of archive: URL) throws -> [String] {
        guard let zip = try? Archive(url: archive, accessMode: .read) else { throw Error.notAnArchive }
        return zip.map(\.path)
    }

    // MARK: - Restore

    /// Unpacks to a staging directory, checks the schema, writes the safety copy, leaves the marker.
    @discardableResult
    public static func stage(_ archive: URL, root: URL, appVersion: String, database: AppDatabase? = nil, safetyCopyDirectory: URL? = nil) throws -> PendingRestore {
        let fm = FileManager.default
        let manifest = try inspect(archive)
        guard !Migrations.isNewer(manifest.schemaVersion, than: Migrations.currentSchemaVersion) else { throw Error.newerSchema(manifest.schemaVersion) }
        let staging = root.appending(path: stagingName, directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try fm.unzipItem(at: archive, to: staging)
        guard fm.fileExists(atPath: staging.appending(path: databaseName).path) else { try? fm.removeItem(at: staging); throw Error.incomplete }
        // The copy must open before the phone's archive is touched.
        _ = try DatabaseQueue(path: staging.appending(path: databaseName).path).read { try String.fetchOne($0, sql: "pragma schema_version") }
        try? fm.removeItem(at: staging.appending(path: manifestName))

        // Dated to the second and never overwritten: a second restore the same day keeps the first copy.
        let copies = try safetyCopyDirectory ?? Self.safetyCopyDirectory()
        let safety = freeName(in: copies, stem: "Lifeline-before-restore-\(stamp(.now))")
        try export(root: root, appVersion: appVersion, to: safety, database: database)

        let marker = root.appending(path: markerName)
        try JSONEncoder.manifest.encode(manifest).write(to: marker, options: .atomic)
        return PendingRestore(manifest: manifest, safetyCopy: safety)
    }

    /// At launch, before the database opens: swaps the staged copy in, once. Whatever the phone
    /// held at that moment (including anything done after "Replace") is zipped into Documents
    /// before its directory goes, so a restore is never the move that loses a recording. A crash
    /// between the steps is picked up on the next launch: a moved-aside archive is saved, a
    /// finished swap is only tidied. Returns whether a restore was applied.
    @discardableResult
    public static func applyPendingRestore(root: URL, safetyCopyDirectory: URL? = nil) throws -> Bool {
        let fm = FileManager.default
        let marker = root.appending(path: markerName)
        let staging = root.appending(path: stagingName, directoryHint: .isDirectory)
        let current = AudioLocation.rootDirectory(under: root)
        let replaced = root.appending(path: replacedName, directoryHint: .isDirectory)
        let stageReady = fm.fileExists(atPath: staging.appending(path: databaseName).path)
        guard fm.fileExists(atPath: marker.path) else {
            // No restore pending: a leftover stage is noise; a leftover moved-aside archive is data.
            try? fm.removeItem(at: staging)
            preserveAll(under: root, safetyCopyDirectory: safetyCopyDirectory)
            return false
        }
        guard stageReady else {
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: marker)
            preserveAll(under: root, safetyCopyDirectory: safetyCopyDirectory)
            return false
        }
        if fm.fileExists(atPath: current.path) {
            // A previous attempt that crashed after moving the old archive aside left it here: keep it first.
            preserveAll(under: root, safetyCopyDirectory: safetyCopyDirectory)
            // An earlier launch that could not save its moved-aside archive (a full phone) left it
            // in place: this one goes beside it under its own name, so the swap never meets "file exists".
            let aside = fm.fileExists(atPath: replaced.path)
                ? root.appending(path: "\(replacedName)-\(UUID().uuidString)", directoryHint: .isDirectory) : replaced
            try fm.moveItem(at: current, to: aside)
        }
        try fm.moveItem(at: staging, to: current)
        let audio = current.appending(path: audioDirectory, directoryHint: .isDirectory)
        try fm.createDirectory(at: audio, withIntermediateDirectories: true)
        try AudioLocation.applyBackupExclusion(to: audio)
        try? fm.removeItem(at: marker)
        preserveAll(under: root, safetyCopyDirectory: safetyCopyDirectory)
        return true
    }

    /// Every moved-aside archive under `root` (`Lifeline-replaced`, and `Lifeline-replaced-<id>`
    /// when an earlier one could not be saved yet), each saved or left for the next launch.
    private static func preserveAll(under root: URL, safetyCopyDirectory: URL?) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names.sorted() where name == replacedName || name.hasPrefix(replacedName + "-") {
            preserve(root.appending(path: name, directoryHint: .isDirectory), safetyCopyDirectory: safetyCopyDirectory)
        }
    }

    /// Zips a moved-aside archive into Documents and removes the directory. A failure (a full
    /// phone, say) never throws: the directory stays where it is and the next launch tries
    /// again, so a restore cannot lock the person out of the app.
    private static func preserve(_ directory: URL, safetyCopyDirectory: URL?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.appending(path: databaseName).path) else { try? fm.removeItem(at: directory); return }
        do {
            let copies = try safetyCopyDirectory ?? Self.safetyCopyDirectory()
            let destination = freeName(in: copies, stem: "Lifeline-replaced-\(stamp(.now))")
            try export(appDirectory: directory, appVersion: "replaced", to: destination, database: nil, progress: { _ in })
            try fm.removeItem(at: directory)
        } catch {
            print("[backup] could not save the replaced archive yet: \(error)")
        }
    }

    /// Tests: an archive with its manifest changed.
    public static func rewritingManifest(of archive: URL, _ change: (inout BackupManifest) -> Void) throws -> URL {
        var manifest = try inspect(archive)
        change(&manifest)
        let fm = FileManager.default
        let out = archive.deletingLastPathComponent().appending(path: "rewritten-\(UUID().uuidString).lifeline")
        try fm.copyItem(at: archive, to: out)
        let zip = try Archive(url: out, accessMode: .update)
        if let entry = zip[manifestName] { try zip.remove(entry) }
        let data = try JSONEncoder.manifest.encode(manifest)
        try zip.addEntry(with: manifestName, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
        return out
    }

    // MARK: - Helpers

    /// A consistent copy: WAL checkpointed into it, through the backup API, never a file copy.
    private static func copyDatabase(from source: URL, to destination: URL, database: AppDatabase?) throws -> (sessions: Int, memories: Int) {
        let target = try DatabaseQueue(path: destination.path)
        if let database {
            try database.writer.backup(to: target)
        } else {
            let opened = try DatabaseQueue(path: source.path)
            try opened.backup(to: target)
        }
        return try target.read { db in
            (try Int.fetchOne(db, sql: "select count(*) from session") ?? 0,
             try Int.fetchOne(db, sql: "select count(*) from memory where created_from_candidate_id is not null") ?? 0)
        }
    }

    private static func schemaVersion(of database: URL) throws -> String {
        let queue = try DatabaseQueue(path: database.path)
        let applied = try queue.read { try String.fetchAll($0, sql: "select identifier from grdb_migrations") }
        return Migrations.versions.last { applied.contains($0) } ?? "v0"
    }

    /// "2026-10-24-093015": the day, then the time to the second.
    static func stamp(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static func day(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

private extension JSONEncoder {
    static var manifest: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
}

private extension JSONDecoder {
    static var manifest: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
