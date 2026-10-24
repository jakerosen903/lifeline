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

    /// A row of this extraction that carries on an earlier, pending card (M5).
    public struct Continuation: Sendable, Equatable {
        public var earlierID: CandidateID
        /// The superseded row stored for it in this extraction.
        public var rowID: CandidateID
        public var span: ExtraSpan
        public init(earlierID: CandidateID, rowID: CandidateID, span: ExtraSpan) { self.earlierID = earlierID; self.rowID = rowID; self.span = span }
    }

    /// Writes every candidate of one extraction, marks the segment extracted, and grows each
    /// continued card by its new span, in one transaction: a kill cannot leave half the rows
    /// behind a pending segment, or an extracted segment whose span no card carries. A card that
    /// stopped being pending in the meantime (Keep landed first) is not grown; its continuation
    /// row becomes an ordinary pending card that names the kept memory instead.
    /// Returns the ids of the cards that were grown.
    @discardableResult
    public func insertAll(_ candidates: [Candidate], markingExtracted segment: SegmentID, in sessions: SessionRepository,
                          extending continuations: [Continuation] = []) throws -> Set<CandidateID> {
        do {
            return try db.writer.write { db in
                for candidate in candidates { try candidate.insert(db) }
                try db.execute(sql: "update segment set status = ? where id = ?", arguments: [SegmentStatus.extracted.rawValue, segment.rawValue])
                var grown: Set<CandidateID> = []
                for continuation in continuations {
                    if let earlier = try Candidate.fetchOne(db, key: continuation.earlierID.rawValue), earlier.status == .pending,
                       var out = CandidatePayload.memory(earlier) {
                        out.extraSpans.append(continuation.span)
                        try db.execute(sql: "update candidate set payload = ? where id = ? and status = ?",
                                       arguments: [try CandidatePayload.encode(out), earlier.id.rawValue, CandidateStatus.pending.rawValue])
                        grown.insert(earlier.id)
                    } else if let row = try Candidate.fetchOne(db, key: continuation.rowID.rawValue), var out = CandidatePayload.memory(row) {
                        let kept = try String.fetchOne(db, sql: """
                            select id from memory where created_from_candidate_id = ?
                            union select memory_id from memory_span where candidate_id = ? limit 1
                            """, arguments: [continuation.earlierID.rawValue, continuation.earlierID.rawValue])
                        if let kept { out.sameAsMemoryIDs = [kept] + out.sameAsMemoryIDs.filter { $0 != kept } }
                        out.continuesCandidateID = nil
                        try db.execute(sql: "update candidate set payload = ?, status = ?, rejection = null where id = ?",
                                       arguments: [try CandidatePayload.encode(out), CandidateStatus.pending.rawValue, row.id.rawValue])
                    }
                }
                return grown
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

    /// Status only: a continuation row keeps its "continues <id>" marker when its card is kept (M5).
    public func setStatusKeepingRejection(_ id: CandidateID, _ status: CandidateStatus) throws {
        try db.writer.write { db in
            try db.execute(sql: "update candidate set status = ? where id = ?", arguments: [status.rawValue, id.rawValue])
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
