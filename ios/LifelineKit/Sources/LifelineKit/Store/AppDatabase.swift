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
        case stageLog = "stage_log", landingChoiceMade = "landing_choice_made", kind, hiddenFromTimeline = "hidden_from_timeline"
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
}

extension Chapter: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "chapter"
    enum CodingKeys: String, CodingKey { case id, title, range, order }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ChapterColumns.self)
        id = try c.decode(ChapterID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        order = try c.decode(Int.self, forKey: .order)
        range = TimeRange(earliest: try c.decodeIfPresent(CivilDate.self, forKey: .earliest),
                          latest: try c.decodeIfPresent(CivilDate.self, forKey: .latest),
                          likelyStart: try c.decodeIfPresent(CivilDate.self, forKey: .likelyStart),
                          likelyEnd: try c.decodeIfPresent(CivilDate.self, forKey: .likelyEnd),
                          granularity: try c.decodeIfPresent(Granularity.self, forKey: .granularity),
                          origin: try c.decodeIfPresent(RangeOrigin.self, forKey: .origin),
                          evidenceText: try c.decodeIfPresent(String.self, forKey: .evidenceText))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ChapterColumns.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(order, forKey: .order)
        try c.encode(range.earliest, forKey: .earliest)
        try c.encode(range.latest, forKey: .latest)
        try c.encode(range.likelyStart, forKey: .likelyStart)
        try c.encode(range.likelyEnd, forKey: .likelyEnd)
        try c.encode(range.granularity, forKey: .granularity)
        try c.encode(range.origin, forKey: .origin)
        try c.encode(range.evidenceText, forKey: .evidenceText)
    }
}

enum ChapterColumns: String, CodingKey {
    case id, title, order
    case earliest, latest, likelyStart = "likely_start", likelyEnd = "likely_end", granularity, origin, evidenceText = "evidence_text"
}

extension Collection: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "collection"
}

extension CollectionMemory: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "collection_memory"
    enum CodingKeys: String, CodingKey { case collectionID = "collection_id", memoryID = "memory_id" }
}

extension CuriosityItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "curiosity_item"
    enum CodingKeys: String, CodingKey {
        case id, kind, text, payoffCount = "payoff_count", status, sourceMemoryID = "source_memory_id", targetMemoryID = "target_memory_id"
    }
}

extension MemorySpan: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "memory_span"
    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id", segmentID = "segment_id", startMs = "start_ms", endMs = "end_ms", order
        case titleText = "title_text", candidateID = "candidate_id"
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
    enum CodingKeys: String, CodingKey { case id, segmentID = "segment_id", text, status, personID = "person_id", relationText = "relation_text" }
}

extension Anchor: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anchor"
    enum CodingKeys: String, CodingKey {
        case id, memoryID = "memory_id", phrase, relation, targetKind = "target_kind", targetID = "target_id", targetText = "target_text", value, resolved
    }
}
