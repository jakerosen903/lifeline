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

    /// Column-scoped writes: the recorder, the arc and the landing each own one column, so none
    /// overwrites another's with a stale copy of the row.
    public func updateStageLog(_ id: SessionID, _ stageLog: String) throws {
        try db.writer.write { try $0.execute(sql: "UPDATE session SET stage_log = ? WHERE id = ?", arguments: [stageLog, id.rawValue]) }
    }

    public func markEnded(_ id: SessionID, at date: Date) throws {
        try db.writer.write { try $0.execute(sql: "UPDATE session SET ended_at = ? WHERE id = ?", arguments: [date, id.rawValue]) }
    }

    /// Appends `reason` to the session's stage log (stage `ended`).
    public func appendToStageLog(_ id: SessionID, reason: String, at date: Date) throws {
        try db.writer.write { db in
            let current = try String.fetchOne(db, sql: "SELECT stage_log FROM session WHERE id = ?", arguments: [id.rawValue]) ?? "[]"
            var log = (try? SessionArc.decode(current)) ?? []
            log.append(StageChange(stage: .ended, at: date, reason: reason))
            try db.execute(sql: "UPDATE session SET stage_log = ? WHERE id = ?", arguments: [try SessionArc.encode(log), id.rawValue])
        }
    }

    /// The person left the landing (or had nothing to land): logged, and never shown again.
    public func markLanded(_ id: SessionID, now: Date = .now) throws {
        try appendToStageLog(id, reason: "landed", at: now)
        try db.writer.write { try $0.execute(sql: "UPDATE session SET landing_choice_made = 1 WHERE id = ?", arguments: [id.rawValue]) }
    }

    public func setHidden(_ id: SessionID, _ hidden: Bool) throws {
        try db.writer.write { try $0.execute(sql: "UPDATE session SET hidden_from_timeline = ? WHERE id = ?", arguments: [hidden, id.rawValue]) }
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
    /// Deleting a recording removes the tellings recorded in it. A memory that keeps a telling
    /// from another recording survives, renumbered so its earliest telling is order 0; a memory
    /// with no telling left goes with the recording (M4.1).
    public func deleteSession(_ id: SessionID) throws {
        try db.writer.write { db in
            let touched = try String.fetchAll(db, sql: """
                select distinct memory_span.memory_id from memory_span
                join segment on segment.id = memory_span.segment_id where segment.session_id = ?
                """, arguments: [id.rawValue])
            try db.execute(sql: """
                delete from memory_span where segment_id in (select id from segment where session_id = ?)
                """, arguments: [id.rawValue])
            for memory in touched {
                let spans = try Row.fetchAll(db, sql: """
                    select memory_span.rowid as rid, memory_span.candidate_id as cid, memory_span."order" as old_order, memory_span.continues_order as cont from memory_span
                    join segment on segment.id = memory_span.segment_id
                    where memory_span.memory_id = ? order by segment."index", memory_span.start_ms
                    """, arguments: [memory])
                guard !spans.isEmpty else {
                    _ = try Memory.deleteOne(db, key: memory)
                    continue
                }
                // Two passes so the (memory_id, order) key never collides mid-renumber. A continuation
                // follows its telling through the same old→new map; one whose telling left stands alone.
                let newOrder = Dictionary(uniqueKeysWithValues: spans.enumerated().map { ($1["old_order"] as Int, $0) })
                for (i, row) in spans.enumerated() {
                    let cont = (row["cont"] as Int?).flatMap { newOrder[$0] }
                    try db.execute(sql: "update memory_span set \"order\" = ?, continues_order = ? where rowid = ?", arguments: [-(i + 1), cont, row["rid"] as Int64])
                }
                try db.execute(sql: "update memory_span set \"order\" = -\"order\" - 1 where memory_id = ?", arguments: [memory])
                // The memory's own card may be leaving with the recording; its first surviving telling takes over.
                let ownCandidateLeaving = try Bool.fetchOne(db, sql: """
                    select exists(select 1 from memory join candidate on candidate.id = memory.created_from_candidate_id
                                  join segment on segment.id = candidate.segment_id where memory.id = ? and segment.session_id = ?)
                    """, arguments: [memory, id.rawValue]) ?? false
                if ownCandidateLeaving {
                    try db.execute(sql: "update memory set created_from_candidate_id = ? where id = ?", arguments: [spans[0]["cid"] as String?, memory])
                }
            }
            _ = try Session.deleteOne(db, key: id.rawValue)
            try db.execute(sql: MemoryRepository.deleteEmptyStoriesSQL)
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
