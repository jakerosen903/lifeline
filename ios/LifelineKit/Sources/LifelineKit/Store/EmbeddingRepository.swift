import Foundation
import GRDB

/// One sentence-embedding vector per memory, for "Same as X?" (M4.1). Rows go with their
/// memory. The vector is stored as little-endian Float32; `dims` is its length.
public struct EmbeddingRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func upsert(memory: MemoryID, model: String, vector: [Float]) throws {
        try db.writer.write { db in
            try db.execute(sql: "insert or replace into memory_embedding (memory_id, model, dims, vector) values (?, ?, ?, ?)",
                           arguments: [memory.rawValue, model, vector.count, Self.blob(vector)])
        }
    }

    public func vector(of memory: MemoryID) throws -> (model: String, vector: [Float])? {
        try db.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "select model, vector from memory_embedding where memory_id = ?", arguments: [memory.rawValue]) else { return nil }
            return (row["model"], Self.floats(row["vector"]))
        }
    }

    public func all(model: String) throws -> [(MemoryID, [Float])] {
        try db.writer.read { db in
            try Row.fetchAll(db, sql: "select memory_id, vector from memory_embedding where model = ?", arguments: [model])
                .map { (MemoryID(rawValue: $0["memory_id"]), Self.floats($0["vector"])) }
        }
    }

    /// Every memory that has a vector of this model and is not excluded from AI, in one query.
    public func memoriesWithVectors(model: String) throws -> [(memory: Memory, vector: [Float])] {
        try db.writer.read { db in
            try Row.fetchAll(db, sql: """
                select memory.*, memory_embedding.vector as e_vector from memory
                join memory_embedding on memory_embedding.memory_id = memory.id
                where memory_embedding.model = ? and memory.excluded_from_ai = 0
                """, arguments: [model])
                .map { (memory: try Memory(row: $0), vector: Self.floats($0["e_vector"])) }
        }
    }

    public func delete(memory: MemoryID) throws {
        try db.writer.write { try $0.execute(sql: "delete from memory_embedding where memory_id = ?", arguments: [memory.rawValue]) }
    }

    public func memoryIDsWithRows() throws -> Set<MemoryID> {
        try db.writer.read { Set(try String.fetchAll($0, sql: "select memory_id from memory_embedding").map(MemoryID.init(rawValue:))) }
    }

    static func blob(_ vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * 4)
        for value in vector { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    static func floats(_ data: Data) -> [Float] {
        stride(from: 0, to: data.count - data.count % 4, by: 4).map { i in
            let bits = data[data.startIndex + i ..< data.startIndex + i + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return Float(bitPattern: UInt32(littleEndian: bits))
        }
    }
}
