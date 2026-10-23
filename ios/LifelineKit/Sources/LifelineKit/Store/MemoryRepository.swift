import Foundation
import GRDB

/// Memories and their edges. A memory is written with its spans, people, places and anchors
/// in one transaction, so a failure anywhere leaves no half-memory.
public struct MemoryRepository: Sendable {
    public enum Error: Swift.Error, Equatable {
        case noSpan
    }

    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// `acceptingCandidate` marks that candidate accepted in the same transaction, so a kill
    /// can never leave an accepted memory behind a card that is still pending.
    public func insert(_ memory: Memory, spans: [MemorySpan], people: [MemoryPerson], places: [MemoryPlace], anchors: [Anchor],
                       acceptingCandidate candidate: CandidateID? = nil) throws {
        guard !spans.isEmpty else { throw Error.noSpan }
        try db.writer.write { db in
            try memory.insert(db)
            for span in spans { try span.insert(db) }
            for person in people { try person.insert(db) }
            for place in places { try place.insert(db) }
            for anchor in anchors { try anchor.insert(db) }
            if let candidate {
                try db.execute(sql: "update candidate set status = ? where id = ?", arguments: [CandidateStatus.accepted.rawValue, candidate.rawValue])
            }
        }
    }

    public func fetch(_ id: MemoryID) throws -> Memory? {
        try db.writer.read { try Memory.fetchOne($0, key: id.rawValue) }
    }

    /// Memories with a span in this session, in session order (first span's segment, then start).
    public func memories(in session: SessionID) throws -> [Memory] {
        try db.writer.read { db in
            try Memory.fetchAll(db, sql: """
                select memory.* from memory
                join memory_span on memory_span.memory_id = memory.id and memory_span."order" = 0
                join segment on segment.id = memory_span.segment_id
                where segment.session_id = ?
                order by segment."index", memory_span.start_ms, memory.created_at
                """, arguments: [session.rawValue])
        }
    }

    /// Memories created from candidates of this segment.
    public func memories(fromSegment segment: SegmentID) throws -> [Memory] {
        try db.writer.read { db in
            try Memory.fetchAll(db, sql: """
                select memory.* from memory
                join candidate on candidate.id = memory.created_from_candidate_id
                where candidate.segment_id = ?
                order by candidate.ordinal
                """, arguments: [segment.rawValue])
        }
    }

    public func people(of memory: MemoryID) throws -> [Person] {
        try db.writer.read { db in
            try Person.fetchAll(db, sql: """
                select person.* from person
                join memory_person on memory_person.person_id = person.id
                where memory_person.memory_id = ?
                order by person.display_name
                """, arguments: [memory.rawValue])
        }
    }

    public func spans(of memory: MemoryID) throws -> [MemorySpan] {
        try db.writer.read {
            try MemorySpan.filter(Column("memory_id") == memory.rawValue).order(Column("order")).fetchAll($0)
        }
    }

    public func anchors(of memory: MemoryID) throws -> [Anchor] {
        try db.writer.read { try Anchor.filter(Column("memory_id") == memory.rawValue).fetchAll($0) }
    }

    public func places(of memory: MemoryID) throws -> [Place] {
        try db.writer.read { db in
            try Place.fetchAll(db, sql: """
                select place.* from place join memory_place on memory_place.place_id = place.id
                where memory_place.memory_id = ? order by place.name_text
                """, arguments: [memory.rawValue])
        }
    }

    public func updateRange(_ id: MemoryID, _ range: TimeRange) throws {
        try db.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id.rawValue) else { return }
            memory.range = range
            try memory.update(db)
        }
    }

    public func allMemories() throws -> [Memory] {
        try db.writer.read { try Memory.order(Column("created_at")).fetchAll($0) }
    }

    public func memories(inChapter chapter: ChapterID) throws -> [Memory] {
        try db.writer.read { try Memory.filter(Column("chapter_id") == chapter.rawValue).order(Column("created_at")).fetchAll($0) }
    }

    /// Memories with no range at all.
    public func unplacedMemories() throws -> [Memory] {
        try db.writer.read {
            try Memory.filter(Column("earliest") == nil && Column("latest") == nil && Column("likely_start") == nil && Column("likely_end") == nil)
                .order(Column("created_at")).fetchAll($0)
        }
    }

    /// A memory the resolver creates to stand for a target the owner named but has not told
    /// yet. It has no candidate; its span is the span of the memory that named it.
    public func insertFloating(title: String, segment: SegmentID, startMs: Milliseconds, endMs: Milliseconds) throws -> Memory {
        let memory = Memory(id: .init(), title: title, summaryQuote: title, visibility: .timeline, chapterID: nil,
                            createdFromCandidateID: nil, createdAt: .now)
        try insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment, startMs: startMs, endMs: endMs, order: 0)],
                   people: [], places: [], anchors: [])
        return memory
    }

    /// Links a person to a memory; a second link to the same person is a no-op.
    public func link(_ person: PersonID, to memory: MemoryID, roleText: String?) throws {
        try db.writer.write { db in
            try db.execute(sql: "insert or ignore into memory_person (memory_id, person_id, role_text) values (?, ?, ?)",
                           arguments: [memory.rawValue, person.rawValue, roleText])
        }
    }
}
