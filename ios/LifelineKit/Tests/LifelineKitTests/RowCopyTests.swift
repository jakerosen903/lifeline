import Foundation
import GRDB
import Testing
@testable import LifelineKit

// PC-c Task 3: a whole-row copy, so a merge's receipt can put rows back (plan decision 9).

private func thingTable() throws -> AppDatabase {
    let db = try AppDatabase.inMemory()
    try db.writer.write { db in
        try db.execute(sql: """
            create table thing (id text primary key, n integer not null, note text);
            create table part (thing_id text not null references thing(id) on delete cascade, label text not null);
            insert into thing (id, n, note) values ('b', 2, 'second'), ('a', 1, null), ('c', 0, 'left out');
            insert into part (thing_id, label) values ('a', 'handle');
            """)
    }
    return db
}

private func copy(of db: AppDatabase) throws -> RowCopy {
    try db.writer.read { try RowCopy.read("thing", where: "n > ?", arguments: [0], in: $0) }
}

@Test func aCopyReadsWholeRowsInRowidOrderAndInsertsThemBack() throws {
    let db = try thingTable()
    let before = try copy(of: db)
    #expect(before.table == "thing")
    #expect(before.rows.map { $0["id"] } == ["b".databaseValue, "a".databaseValue], "ordered by rowid, not by key")
    #expect(before.rows[1]["note"] == .null, "a null is carried")

    try db.writer.write { db in
        try db.execute(sql: "delete from thing where n > 0")
        try before.insert(in: db)
    }

    #expect(try copy(of: db) == before)
}

@Test func aColumnAddedLaterIsCarried() throws {
    let db = try thingTable()
    try db.writer.write { db in
        try db.execute(sql: "alter table thing add column extra text not null default 'plain'")
        try db.execute(sql: "update thing set extra = 'added later' where id = 'a'")
    }
    let before = try copy(of: db)
    #expect(before.rows[1]["extra"] == "added later".databaseValue)

    try db.writer.write { db in
        try db.execute(sql: "delete from thing where n > 0")
        try before.insert(in: db)
    }

    #expect(try copy(of: db) == before)
}

@Test func anUpdateWritesARowBackWithoutACascade() throws {
    let db = try thingTable()
    let before = try copy(of: db)
    try db.writer.write { try $0.execute(sql: "update thing set n = 9, note = 'changed' where id in ('a', 'b')") }

    try db.writer.write { try before.update(in: $0, key: "id") }

    #expect(try copy(of: db) == before)
    #expect(try db.writer.read { try String.fetchAll($0, sql: "select label from part") } == ["handle"], "no delete ran, so no cascade did")
}

@Test func anEmptyCopyInsertsNothing() throws {
    let db = try thingTable()
    let empty = try db.writer.read { try RowCopy.read("thing", where: "n > ?", arguments: [100], in: $0) }
    #expect(empty.rows.isEmpty)
    try db.writer.write { try empty.insert(in: $0) }
    #expect(try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from thing") } == 3)
}
