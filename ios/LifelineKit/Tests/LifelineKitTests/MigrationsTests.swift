import Testing
import GRDB
@testable import LifelineKit

@Test func v1CreatesAllTables() throws {
    let db = try AppDatabase.inMemory()
    let names = try db.writer.read {
        try String.fetchAll($0, sql: "select name from sqlite_master where type='table' order by name")
    }
    #expect(Set(names).isSuperset(of: ["session", "segment", "word", "profile", "person"]))
}

@Test func foreignKeysAreEnforced() throws {
    let db = try AppDatabase.inMemory()
    let orphan = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "x", status: .pending)
    #expect(throws: DatabaseError.self) {
        try db.writer.write { try orphan.insert($0) }
    }
}
