import Foundation
import GRDB

/// Reads and writes sessions, segments and words.
public struct SessionRepository: Sendable {
    fileprivate let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func insert(_ session: Session) throws {
        try db.writer.write { try session.insert($0) }
    }

    public func update(_ session: Session) throws {
        try db.writer.write { try session.update($0) }
    }

    public func fetch(_ id: SessionID) throws -> Session? {
        try db.writer.read { try Session.fetchOne($0, key: id.rawValue) }
    }

    /// Newest first.
    public func listSessions() throws -> [Session] {
        try db.writer.read { try Session.order(Column("started_at").desc).fetchAll($0) }
    }

    /// Sessions that never landed: `ended_at` is nil.
    public func unfinishedSessions() throws -> [Session] {
        try db.writer.read { try Session.filter(Column("ended_at") == nil).fetchAll($0) }
    }

    /// Inserts a segment and its words in one transaction.
    public func insert(_ segment: Segment, words: [Word]) throws {
        try db.writer.write { db in
            try segment.insert(db)
            for word in words { try word.insert(db) }
        }
    }

    /// In index order.
    public func segments(in session: SessionID) throws -> [Segment] {
        try db.writer.read {
            try Segment.filter(Column("session_id") == session.rawValue).order(Column("index")).fetchAll($0)
        }
    }

    /// In index order.
    public func words(in segment: SegmentID) throws -> [Word] {
        try db.writer.read {
            try Word.filter(Column("segment_id") == segment.rawValue).order(Column("index")).fetchAll($0)
        }
    }
}

extension SessionRepository {
    /// Removes a session and, by cascade, its segments and words.
    public func delete(_ id: SessionID) throws {
        _ = try db.writer.write { try Session.deleteOne($0, key: id.rawValue) }
    }
}
