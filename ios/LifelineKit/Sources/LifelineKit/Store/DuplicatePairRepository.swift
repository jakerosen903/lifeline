import Foundation
import GRDB

/// Pairs the duplicate pass has judged. A decided pair is never asked again; rows go with
/// their memories (cascade).
public struct DuplicatePairRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func insert(_ pair: DuplicatePair) throws {
        try db.writer.write { try pair.insert($0) }
    }

    public func pair(id: DuplicatePairID) throws -> DuplicatePair? {
        try db.writer.read { try DuplicatePair.fetchOne($0, key: id.rawValue) }
    }

    /// Open pairs, oldest first.
    public func open(limit: Int) throws -> [DuplicatePair] {
        try db.writer.read { db in
            try DuplicatePair.filter(Column("status") == PairStatus.open.rawValue).order(Column("rowid")).limit(limit).fetchAll(db)
        }
    }

    /// Every pair that has an answer, as unordered keys.
    public func decided() throws -> Set<PairKey> {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "select a_memory_id, b_memory_id from duplicate_pair where status != ?", arguments: [PairStatus.open.rawValue])
            return Set(rows.map { PairKey(MemoryID(rawValue: $0["a_memory_id"]), MemoryID(rawValue: $0["b_memory_id"])) })
        }
    }

    /// Every pair on file, open or decided, as unordered keys.
    public func known() throws -> Set<PairKey> {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "select a_memory_id, b_memory_id from duplicate_pair")
            return Set(rows.map { PairKey(MemoryID(rawValue: $0["a_memory_id"]), MemoryID(rawValue: $0["b_memory_id"])) })
        }
    }

    public func setStatus(_ id: DuplicatePairID, _ status: PairStatus) throws {
        try db.writer.write { db in
            let decidedAt: Date? = status == .open ? nil : .now
            try db.execute(sql: "update duplicate_pair set status = ?, decided_at = ? where id = ?", arguments: [status.rawValue, decidedAt, id.rawValue])
        }
    }

    public func pairs(touching memory: MemoryID) throws -> [DuplicatePair] {
        try db.writer.read { db in
            try DuplicatePair.filter(Column("a_memory_id") == memory.rawValue || Column("b_memory_id") == memory.rawValue).order(Column("rowid")).fetchAll(db)
        }
    }
}
