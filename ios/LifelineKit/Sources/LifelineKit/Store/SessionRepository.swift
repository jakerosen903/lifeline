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

    /// Sessions whose recording never ended: `ended_at` is nil (a crash, or recording now).
    public func unfinishedSessions() throws -> [Session] {
        try db.writer.read { try Session.filter(Column("ended_at") == nil).fetchAll($0) }
    }

    /// Sessions with words that have not been through their landing, newest first.
    public func unlandedSessions() throws -> [Session] {
        try db.writer.read { db in
            try Session.fetchAll(db, sql: """
                SELECT s.* FROM session s
                WHERE s.landing_choice_made = 0
                  AND EXISTS (SELECT 1 FROM segment g WHERE g.session_id = s.id)
                ORDER BY s.started_at DESC
                """)
        }
    }

    public func markLanded(_ id: SessionID, stageLog: String) throws {
        try db.writer.write { db in
            try db.execute(sql: "UPDATE session SET landing_choice_made = 1, stage_log = ? WHERE id = ?", arguments: [stageLog, id.rawValue])
        }
    }

    /// Sessions with at least one segment still waiting to be sorted, newest first.
    public func sessionsWithPendingSegments() throws -> [Session] {
        try db.writer.read { db in
            try Session.fetchAll(db, sql: """
                SELECT s.* FROM session s
                WHERE EXISTS (SELECT 1 FROM segment g WHERE g.session_id = s.id AND g.status = 'pending')
                ORDER BY s.started_at DESC
                """)
        }
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

    /// Removes the session and everything derived from it: segments, words, candidates, mentions
    /// and prompt-log rows go by cascade; memories told in it (by span or by candidate) are
    /// deleted first, and their spans, anchors, people and places follow them. One transaction.
    public func deleteSession(_ id: SessionID) throws {
        try db.writer.write { db in
            try db.execute(sql: """
                delete from memory where id in (
                    select memory_span.memory_id from memory_span
                    join segment on segment.id = memory_span.segment_id where segment.session_id = ?
                    union
                    select memory.id from memory
                    join candidate on candidate.id = memory.created_from_candidate_id
                    join segment on segment.id = candidate.segment_id where segment.session_id = ?)
                """, arguments: [id.rawValue, id.rawValue])
            _ = try Session.deleteOne(db, key: id.rawValue)
        }
    }
}

extension SessionRepository {
    public func setStatus(_ status: SegmentStatus, for segment: SegmentID) throws {
        try db.writer.write { db in
            try db.execute(sql: "update segment set status = ? where id = ?", arguments: [status.rawValue, segment.rawValue])
        }
    }

    /// In index order, only segments with `status`.
    public func segments(in session: SessionID, status: SegmentStatus) throws -> [Segment] {
        try db.writer.read {
            try Segment.filter(Column("session_id") == session.rawValue && Column("status") == status.rawValue)
                .order(Column("index")).fetchAll($0)
        }
    }

    public func fetchSegment(_ id: SegmentID) throws -> Segment? {
        try db.writer.read { try Segment.fetchOne($0, key: id.rawValue) }
    }
}
