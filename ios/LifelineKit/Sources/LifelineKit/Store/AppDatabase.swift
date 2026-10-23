import Foundation
import GRDB

/// Opens the SQLite file and runs migrations. Repositories take an `AppDatabase`
/// and never expose GRDB types above the Store layer.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Migrations.migrator.migrate(writer)
    }

    /// Opens or creates the database at `url`, creating parent directories.
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(writer: try DatabasePool(path: url.path(percentEncoded: false), configuration: config))
    }

    /// A private in-memory database for tests.
    public static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(writer: try DatabaseQueue(configuration: config))
    }
}

// MARK: - Record conformances (snake_case columns, see Migrations)

extension Session: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "session"
    enum CodingKeys: String, CodingKey {
        case id, startedAt = "started_at", endedAt = "ended_at", audioPath = "audio_path"
        case stageLog = "stage_log", landingChoiceMade = "landing_choice_made"
    }
}

extension Segment: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "segment"
    enum CodingKeys: String, CodingKey {
        case id, sessionID = "session_id", index, startMs = "start_ms", endMs = "end_ms", text, status
    }
}

extension Word: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "word"
    enum CodingKeys: String, CodingKey {
        case segmentID = "segment_id", index, text, startMs = "start_ms", endMs = "end_ms"
    }
}

extension Person: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "person"
    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", notes, isOwner = "is_owner"
        case birthDate = "birth_date", birthDateOrigin = "birth_date_origin"
    }
}

/// The single profile row. Its fixed primary key keeps it a singleton.
struct ProfileRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "profile"
    static let singletonID = 1

    var id: Int = ProfileRow.singletonID
    var displayName: String?
    var birthDate: Date?
    var birthPlaceText: String?
    var freeText: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", birthDate = "birth_date"
        case birthPlaceText = "birth_place_text", freeText = "free_text", updatedAt = "updated_at"
    }

    init(_ p: Profile) {
        displayName = p.displayName; birthDate = p.birthDate; birthPlaceText = p.birthPlaceText
        freeText = p.freeText; updatedAt = p.updatedAt
    }

    var profile: Profile {
        Profile(displayName: displayName, birthDate: birthDate, birthPlaceText: birthPlaceText, freeText: freeText, updatedAt: updatedAt)
    }
}

extension Candidate: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "candidate"
    enum CodingKeys: String, CodingKey {
        case id, segmentID = "segment_id", extractorVersion = "extractor_version", ordinal, kind, payload, confidence, status
        case rejection, createdAt = "created_at"
    }
}

extension Memory: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "memory"
    enum CodingKeys: String, CodingKey {
        case id, title, summaryQuote = "summary_quote", visibility, chapterID = "chapter_id"
        case createdFromCandidateID = "created_from_candidate_id", createdAt = "created_at"
        case earliest, latest, likelyStart = "likely_start", likelyEnd = "likely_end", granularity, origin, evidenceText = "evidence_text"
    }
}

extension MemorySpan: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "memory_span"
    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id", segmentID = "segment_id", startMs = "start_ms", endMs = "end_ms", order
    }
}

extension MemoryPerson: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "memory_person"
    enum CodingKeys: String, CodingKey { case memoryID = "memory_id", personID = "person_id", roleText = "role_text" }
}

extension Place: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "place"
    enum CodingKeys: String, CodingKey { case id, nameText = "name_text", lat, lon }
}

extension MemoryPlace: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "memory_place"
    enum CodingKeys: String, CodingKey { case memoryID = "memory_id", placeID = "place_id" }
}

extension Alias: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "alias"
    enum CodingKeys: String, CodingKey { case personID = "person_id", text }
}

extension Mention: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mention"
    enum CodingKeys: String, CodingKey { case id, segmentID = "segment_id", text, status, personID = "person_id" }
}

extension Anchor: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anchor"
    enum CodingKeys: String, CodingKey {
        case id, memoryID = "memory_id", phrase, relation, targetKind = "target_kind", targetID = "target_id", value, resolved
    }
}
