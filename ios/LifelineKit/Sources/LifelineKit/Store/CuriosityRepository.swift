import Foundation
import GRDB

/// What the interviewer would ask next. Anchor items are owned by the resolver: each run
/// replaces the open set so stale questions close themselves.
public struct CuriosityRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// Biggest payoff first; at equal payoff a dated question before an entity question (M7); then by text.
    public func open() throws -> [CuriosityItem] {
        try db.writer.read {
            try CuriosityItem.fetchAll($0, sql: """
                select * from curiosity_item where status = ?
                order by payoff_count desc, case when kind = ? then 0 else 1 end, text collate nocase
                """, arguments: [CuriosityStatus.open.rawValue, CuriosityKind.unresolvedAnchor.rawValue])
        }
    }

    /// The entity questions (M7), owned by the resolver run like anchor items. One transaction:
    /// an open item no longer wanted is answered (a moment arrived); a wanted one is refreshed or
    /// inserted, unless the person dismissed that question before.
    public func replaceOpenEntityItems(_ items: [CuriosityItem]) throws {
        try db.writer.write { db in
            let kinds = [CuriosityKind.entityWithoutMoment, .personWithoutMoment, .ideaWithoutMoment].map(\.rawValue)
            let all = try CuriosityItem.filter(kinds.contains(Column("kind"))).fetchAll(db)
            func key(_ item: CuriosityItem) -> String { "\(item.kind.rawValue)|\(item.entityID?.rawValue ?? "")" }
            let wanted = Dictionary(items.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
            for var old in all where old.status == .open {
                if let fresh = wanted[key(old)] {
                    old.text = fresh.text
                    try old.update(db)
                } else {
                    old.status = .answered
                    try old.update(db)
                }
            }
            let openKeys = Set(all.filter { $0.status == .open }.map(key))
            let declined = Set(all.filter { $0.status == .dismissed }.map(key))
            for item in items where !openKeys.contains(key(item)) && !declined.contains(key(item)) {
                var row = item
                row.status = .open
                try row.insert(db)
            }
        }
    }

    /// One transaction: open `unresolvedAnchor` items whose target is not in `items` are
    /// dismissed; items with a known target are updated in place; the rest are inserted.
    public func replaceOpenAnchorItems(_ items: [CuriosityItem]) throws {
        try db.writer.write { db in
            let existing = try CuriosityItem
                .filter(Column("status") == CuriosityStatus.open.rawValue && Column("kind") == CuriosityKind.unresolvedAnchor.rawValue)
                .fetchAll(db)
            let wanted = Dictionary(items.compactMap { item in item.targetMemoryID.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
            for var old in existing {
                if let target = old.targetMemoryID, let fresh = wanted[target] {
                    old.text = fresh.text
                    old.payoffCount = fresh.payoffCount
                    old.sourceMemoryID = fresh.sourceMemoryID
                    try old.update(db)
                } else {
                    old.status = .dismissed
                    try old.update(db)
                }
            }
            let known = Set(existing.compactMap(\.targetMemoryID))
            for item in items where item.targetMemoryID.map({ !known.contains($0) }) ?? true {
                var row = item
                row.status = .open
                try row.insert(db)
            }
        }
    }

    public func setStatus(_ id: CuriosityItemID, _ status: CuriosityStatus) throws {
        try db.writer.write { db in
            try db.execute(sql: "update curiosity_item set status = ? where id = ?", arguments: [status.rawValue, id.rawValue])
        }
    }

    public func item(forTarget target: MemoryID) throws -> CuriosityItem? {
        try db.writer.read {
            try CuriosityItem.filter(Column("target_memory_id") == target.rawValue && Column("status") == CuriosityStatus.open.rawValue).fetchOne($0)
        }
    }
}
