import Foundation
import GRDB

/// Candidate rows. Insert is guarded by the `(segment_id, extractor_version, ordinal)` unique
/// index so re-running a version is a no-op; status is the only thing that changes afterwards.
public struct CandidateRepository: Sendable {
    public enum Error: Swift.Error, Equatable {
        case duplicate
    }

    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func insert(_ candidate: Candidate) throws {
        do {
            try db.writer.write { try candidate.insert($0) }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw Error.duplicate
        }
    }

    /// Writes every candidate of one extraction and marks the segment extracted in one
    /// transaction, so a kill cannot leave half the rows behind a pending segment.
    public func insertAll(_ candidates: [Candidate], markingExtracted segment: SegmentID, in sessions: SessionRepository) throws {
        do {
            try db.writer.write { db in
                for candidate in candidates { try candidate.insert(db) }
                try db.execute(sql: "update segment set status = ? where id = ?", arguments: [SegmentStatus.extracted.rawValue, segment.rawValue])
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw Error.duplicate
        }
    }

    public func setStatus(_ id: CandidateID, _ status: CandidateStatus, rejection: String? = nil) throws {
        try db.writer.write { db in
            try db.execute(sql: "update candidate set status = ?, rejection = ? where id = ?",
                           arguments: [status.rawValue, rejection, id.rawValue])
        }
    }

    /// A card's payload changed in place: a continuation added a span (M5). The row's identity,
    /// kind and status stay, so the stack and the timeline keep showing one card.
    public func updatePayload(_ id: CandidateID, _ payload: String) throws {
        try db.writer.write { db in
            try db.execute(sql: "update candidate set payload = ? where id = ?", arguments: [payload, id.rawValue])
        }
    }

    /// The rows stored as continuations of a card, in arrival order (M5).
    public func continuations(of id: CandidateID) throws -> [Candidate] {
        try db.writer.read { db in
            try Candidate.filter(Column("rejection") == Self.continuesReason(id)).order(Column("created_at"), Column("ordinal")).fetchAll(db)
        }
    }

    public static func continuesReason(_ id: CandidateID) -> String { "continues \(id.rawValue)" }

    public func fetch(_ id: CandidateID) throws -> Candidate? {
        try db.writer.read { try Candidate.fetchOne($0, key: id.rawValue) }
    }

    /// In ordinal order.
    public func candidates(for segment: SegmentID) throws -> [Candidate] {
        try db.writer.read {
            try Candidate.filter(Column("segment_id") == segment.rawValue).order(Column("ordinal")).fetchAll($0)
        }
    }

    /// Every pending candidate of a session: segment index first, then ordinal.
    /// Every candidate row of the session, whatever its status, in session order.
    public func candidates(in session: SessionID) throws -> [Candidate] {
        try db.writer.read { db in
            try Candidate.fetchAll(db, sql: """
                select candidate.* from candidate
                join segment on segment.id = candidate.segment_id
                where segment.session_id = ?
                order by segment."index", candidate.ordinal
                """, arguments: [session.rawValue])
        }
    }

    public func pending(in session: SessionID) throws -> [Candidate] {
        try db.writer.read { db in
            try Candidate.fetchAll(db, sql: """
                select candidate.* from candidate
                join segment on segment.id = candidate.segment_id
                where segment.session_id = ? and candidate.status = 'pending'
                order by segment."index", candidate.ordinal
                """, arguments: [session.rawValue])
        }
    }

    /// Memory and person candidates the owner dismissed (not ones the validator rejected or the app withheld).
    public func dismissed(in session: SessionID) throws -> [Candidate] {
        try db.writer.read { db in
            try Candidate.fetchAll(db, sql: """
                select candidate.* from candidate
                join segment on segment.id = candidate.segment_id
                where segment.session_id = ? and candidate.status = 'dismissed' and candidate.rejection is null
                  and candidate.kind in ('memory', 'person')
                order by segment."index", candidate.ordinal
                """, arguments: [session.rawValue])
        }
    }

    /// True when any candidate of this version exists for the segment.
    public func hasCandidates(for segment: SegmentID, version: String) throws -> Bool {
        try db.writer.read { db in
            try Candidate.filter(Column("segment_id") == segment.rawValue && Column("extractor_version") == version).fetchCount(db) > 0
        }
    }
}
