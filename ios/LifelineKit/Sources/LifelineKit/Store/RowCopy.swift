import Foundation
import GRDB

/// Whole rows of one table, read with `select *`, so a column a later migration adds is carried (decision 9).
/// A merge's receipt keeps these, so Undo can put the rows back as they were. `table` and `condition` are the
/// caller's own SQL, never text from the person.
struct RowCopy: Sendable, Equatable {
    var table: String
    /// Column name to value, one dictionary per row, in rowid order.
    var rows: [[String: DatabaseValue]]

    /// The rows that match `condition`, ordered by rowid, so an insert keeps their order.
    static func read(_ table: String, where condition: String, arguments: StatementArguments, in db: Database) throws -> RowCopy {
        let rows = try Row.fetchAll(db, sql: "select * from \(table.quotedDatabaseIdentifier) where \(condition) order by rowid", arguments: arguments)
        return RowCopy(table: table, rows: rows.map { row in Dictionary(row.map { ($0, $1) }, uniquingKeysWith: { first, _ in first }) })
    }

    /// Inserts every row, in order. A row is new to the table: a row with the same key makes this throw.
    func insert(in db: Database) throws {
        for row in rows {
            let columns = row.keys.sorted()
            let names = columns.map(\.quotedDatabaseIdentifier).joined(separator: ", ")
            let marks = Array(repeating: "?", count: columns.count).joined(separator: ", ")
            try db.execute(sql: "insert into \(table.quotedDatabaseIdentifier) (\(names)) values (\(marks))",
                           arguments: StatementArguments(columns.map { row[$0] }))
        }
    }

    /// Writes each row over the row with the same value in `key`, with an UPDATE. No delete runs, so no cascade does.
    func update(in db: Database, key: String) throws {
        for row in rows {
            guard let id = row[key] else { continue }
            let columns = row.keys.filter { $0 != key }.sorted()
            guard !columns.isEmpty else { continue }
            let assignments = columns.map { "\($0.quotedDatabaseIdentifier) = ?" }.joined(separator: ", ")
            try db.execute(sql: "update \(table.quotedDatabaseIdentifier) set \(assignments) where \(key.quotedDatabaseIdentifier) = ?",
                           arguments: StatementArguments(columns.map { row[$0] } + [id]))
        }
    }
}
