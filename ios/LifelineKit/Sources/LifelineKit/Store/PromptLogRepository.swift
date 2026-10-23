import Foundation
import GRDB

/// Which prompt opened which session, so the chooser never repeats itself.
public struct PromptLogRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func record(promptID: String, session: SessionID, at date: Date = .now) throws {
        try db.writer.write { db in
            try db.execute(sql: "insert or replace into prompt_log (prompt_id, session_id, used_at) values (?, ?, ?)",
                           arguments: [promptID, session.rawValue, date])
        }
    }

    /// Each prompt id to the most recent time it opened a session.
    public func lastUsed() throws -> [String: Date] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "select prompt_id, max(used_at) as used_at from prompt_log group by prompt_id")
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["prompt_id"] as String, $0["used_at"] as Date) })
        }
    }
}
