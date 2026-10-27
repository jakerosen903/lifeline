import Foundation
import GRDB

/// What the interviewer said in each session, on the session file's clock.
public struct InterviewerTurnRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func insert(_ turn: InterviewerTurn) throws {
        try db.writer.write { try turn.insert($0) }
    }

    /// Stamps the end of a turn; `interrupted` records that the person spoke over it.
    public func end(_ id: InterviewerTurnID, atMs endMs: Milliseconds, interrupted: Bool) throws {
        try db.writer.write {
            try $0.execute(sql: "update interviewer_turn set end_ms = ?, interrupted = ? where id = ?",
                           arguments: [endMs, interrupted, id.rawValue])
        }
    }

    /// In file order. Turns with the same start keep the order they were stored in: the scripted voice
    /// stamps back-to-back turns with one clock value.
    public func turns(in session: SessionID) throws -> [InterviewerTurn] {
        try db.writer.read {
            try InterviewerTurn.filter(Column("session_id") == session.rawValue).order(Column("start_ms"), Column.rowID).fetchAll($0)
        }
    }
}
