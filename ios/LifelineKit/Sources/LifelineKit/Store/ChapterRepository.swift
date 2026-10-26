import Foundation
import GRDB

/// Chapters, collections and membership. A collection's span is derived from its placed members.
public struct ChapterRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    // MARK: - Chapters

    public func chapters() throws -> [Chapter] {
        try db.writer.read { try Chapter.order(Column("order")).fetchAll($0) }
    }

    public func chapter(id: ChapterID) throws -> Chapter? {
        try db.writer.read { try Chapter.fetchOne($0, key: id.rawValue) }
    }

    /// Appends a chapter after the existing ones.
    public func insertChapter(title: String?) throws -> Chapter {
        try db.writer.write { db in
            let order = try Chapter.fetchCount(db)
            let chapter = Chapter(id: .init(), title: title?.trimmingCharacters(in: .whitespacesAndNewlines), range: .unplaced, order: order)
            try chapter.insert(db)
            return chapter
        }
    }

    public func setRange(_ id: ChapterID, _ range: TimeRange) throws {
        try db.writer.write { db in
            guard var chapter = try Chapter.fetchOne(db, key: id.rawValue) else { return }
            chapter.range = range
            try chapter.update(db)
        }
    }

    public func assign(memory: MemoryID, toChapter chapter: ChapterID?) throws {
        try db.writer.write { db in
            try db.execute(sql: "update memory set chapter_id = ? where id = ?", arguments: [chapter?.rawValue, memory.rawValue])
        }
    }

    // MARK: - Collections

    public func collections() throws -> [Collection] {
        try db.writer.read { try Collection.order(Column("title").collating(.nocase)).fetchAll($0) }
    }

    /// Reuses a collection with the same title, ignoring case and outer whitespace.
    public func insertCollection(titled title: String) throws -> Collection {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return try db.writer.write { db in
            if let existing = try Collection.fetchOne(db, sql: "select * from collection where lower(trim(title)) = ?", arguments: [clean.lowercased()]) {
                return existing
            }
            let collection = Collection(id: .init(), title: clean)
            try collection.insert(db)
            return collection
        }
    }

    /// No-op when the memory is already a member.
    public func add(memory: MemoryID, to collection: CollectionID) throws {
        try db.writer.write { db in
            try db.execute(sql: "insert or ignore into collection_memory (collection_id, memory_id) values (?, ?)",
                           arguments: [collection.rawValue, memory.rawValue])
        }
    }

    public func remove(memory: MemoryID, from collection: CollectionID) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from collection_memory where collection_id = ? and memory_id = ?",
                           arguments: [collection.rawValue, memory.rawValue])
        }
    }

    public func members(of collection: CollectionID) throws -> [Memory] {
        try db.writer.read { db in
            try Memory.fetchAll(db, sql: """
                select memory.* from memory join collection_memory cm on cm.memory_id = memory.id
                where cm.collection_id = ? order by memory.earliest is null, memory.earliest, memory.created_at
                """, arguments: [collection.rawValue])
        }
    }

    public func collections(of memory: MemoryID) throws -> [Collection] {
        try db.writer.read { db in
            try Collection.fetchAll(db, sql: """
                select collection.* from collection join collection_memory cm on cm.collection_id = collection.id
                where cm.memory_id = ? order by collection.title collate nocase
                """, arguments: [memory.rawValue])
        }
    }

    /// Earliest of the members' earliest to latest of their latest. Reads as a guess when any
    /// member is a guess, plainly only when every member is stated or confirmed. Unplaced when
    /// no member is placed.
    public func derivedSpan(of collection: CollectionID) throws -> TimeRange {
        Self.span(over: try members(of: collection).filter(\.isMoment).map(\.range))   // a fact's range is hidden everywhere (M7)
    }

    public static func span(over ranges: [TimeRange]) -> TimeRange {
        let placed = ranges.filter(\.isPlaced)
        guard let earliest = placed.compactMap(\.earliest).min(), let latest = placed.compactMap(\.latest).max() else { return .unplaced }
        let anyGuess = placed.contains { $0.origin == .inferred }
        return TimeRange(earliest: earliest, latest: latest, likelyStart: nil, likelyEnd: nil, granularity: .year,
                         origin: anyGuess ? .inferred : .derived, evidenceText: nil)
    }
}
