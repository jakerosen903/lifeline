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

    /// Removes a memory and, by cascade, its spans, people, places and anchors.
    public func delete(_ id: MemoryID) throws {
        _ = try db.writer.write { try Memory.deleteOne($0, key: id.rawValue) }
    }

    public func fetch(_ id: MemoryID) throws -> Memory? {
        try db.writer.read { try Memory.fetchOne($0, key: id.rawValue) }
    }

    /// Memories told in this session, in session order (first span's segment, then start).
    /// Stand-ins the resolver made borrow a span here but are not told stories; they are left out
    /// unless asked for.
    public func memories(in session: SessionID, includingStandIns: Bool = false) throws -> [Memory] {
        try db.writer.read { db in
            try Memory.fetchAll(db, sql: """
                select memory.* from memory
                join memory_span on memory_span.memory_id = memory.id and memory_span."order" = 0
                join segment on segment.id = memory_span.segment_id
                where segment.session_id = ? and (? or memory.created_from_candidate_id is not null)
                order by segment."index", memory_span.start_ms, memory.created_at
                """, arguments: [session.rawValue, includingStandIns])
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

    // MARK: - Spans (M4.1: a memory told more than once)

    public func insertSpan(_ span: MemorySpan) throws {
        try db.writer.write { try span.insert($0) }
    }

    public func deleteSpans(of memory: MemoryID) throws {
        try db.writer.write { try $0.execute(sql: "delete from memory_span where memory_id = ?", arguments: [memory.rawValue]) }
    }

    /// One past the highest order, so a new telling goes last.
    public func nextSpanOrder(of memory: MemoryID) throws -> Int {
        try db.writer.read { db in
            (try Int.fetchOne(db, sql: "select max(\"order\") from memory_span where memory_id = ?", arguments: [memory.rawValue]) ?? -1) + 1
        }
    }

    /// Every telling recorded in this session, with its memory, in session order. Stand-ins
    /// are left out as in `memories(in:)`; a later span of any real memory counts.
    public func spans(in session: SessionID) throws -> [(Memory, MemorySpan)] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select memory.*, memory_span.memory_id as s_memory_id, memory_span.segment_id as s_segment_id, memory_span.start_ms as s_start_ms,
                       memory_span.end_ms as s_end_ms, memory_span."order" as s_order, memory_span.title_text as s_title_text, memory_span.candidate_id as s_candidate_id
                from memory_span
                join memory on memory.id = memory_span.memory_id
                join segment on segment.id = memory_span.segment_id
                where segment.session_id = ? and memory.created_from_candidate_id is not null
                order by segment."index", memory_span.start_ms, memory.created_at
                """, arguments: [session.rawValue])
            return try rows.map { row in
                let memory = try Memory(row: row)
                let span = MemorySpan(memoryID: MemoryID(rawValue: row["s_memory_id"]), segmentID: SegmentID(rawValue: row["s_segment_id"]),
                                      startMs: row["s_start_ms"], endMs: row["s_end_ms"], order: row["s_order"],
                                      titleText: row["s_title_text"], candidateID: (row["s_candidate_id"] as String?).map(CandidateID.init(rawValue:)))
                return (memory, span)
            }
        }
    }

    /// The memory a card was merged into as a later telling, if any.
    public func memory(withSpanFrom candidate: CandidateID) throws -> Memory? {
        try db.writer.read { db in
            try Memory.fetchOne(db, sql: "select memory.* from memory join memory_span on memory_span.memory_id = memory.id where memory_span.candidate_id = ? limit 1",
                                arguments: [candidate.rawValue])
        }
    }

    /// A stand-in becomes a real memory when a telling is merged into it.
    public func updateFields(_ id: MemoryID, title: String, summaryQuote: String, createdFromCandidateID: CandidateID?) throws {
        try db.writer.write { db in
            try db.execute(sql: "update memory set title = ?, summary_quote = ?, created_from_candidate_id = ? where id = ?",
                           arguments: [title, summaryQuote, createdFromCandidateID?.rawValue, id.rawValue])
        }
    }

    // MARK: - Snapshot (M4.1: undo a merge)

    /// Everything a memory owns, so a merge can be taken back exactly.
    public struct Snapshot: Sendable, Equatable {
        public var memory: Memory
        public var spans: [MemorySpan]
        public var people: [MemoryPerson]
        public var places: [MemoryPlace]
        public var anchors: [Anchor]
        public var collectionIDs: [CollectionID]
        public var takenAt: Date
    }

    public func snapshot(of id: MemoryID) throws -> Snapshot? {
        try db.writer.read { db in
            guard let memory = try Memory.fetchOne(db, key: id.rawValue) else { return nil }
            return Snapshot(
                memory: memory,
                spans: try MemorySpan.filter(Column("memory_id") == id.rawValue).order(Column("order")).fetchAll(db),
                people: try MemoryPerson.filter(Column("memory_id") == id.rawValue).fetchAll(db),
                places: try MemoryPlace.filter(Column("memory_id") == id.rawValue).fetchAll(db),
                anchors: try Anchor.filter(Column("memory_id") == id.rawValue).fetchAll(db),
                collectionIDs: try String.fetchAll(db, sql: "select collection_id from collection_memory where memory_id = ?", arguments: [id.rawValue]).map(CollectionID.init(rawValue:)),
                takenAt: .now)
        }
    }

    /// Puts the memory back exactly as the snapshot has it, re-creating the row if it was deleted.
    public func restore(_ snapshot: Snapshot) throws {
        try db.writer.write { db in
            let id = snapshot.memory.id.rawValue
            try snapshot.memory.save(db)
            for table in ["memory_span", "memory_person", "memory_place", "anchor", "collection_memory"] {
                try db.execute(sql: "delete from \(table) where memory_id = ?", arguments: [id])
            }
            for span in snapshot.spans { try span.insert(db) }
            for person in snapshot.people { try person.insert(db) }
            for place in snapshot.places { try place.insert(db) }
            for anchor in snapshot.anchors { try anchor.insert(db) }
            for collection in snapshot.collectionIDs {
                try db.execute(sql: "insert or ignore into collection_memory (collection_id, memory_id) values (?, ?)", arguments: [collection.rawValue, id])
            }
        }
    }

    /// Re-points every edge of `source` at `target` and appends its spans after the target's.
    /// Collections and the chapter move only when the target has none. The source row is deleted.
    public func fold(_ source: MemoryID, into target: MemoryID, sourceTitle: String, sourceCandidate: CandidateID?) throws {
        try db.writer.write { db in
            let next = (try Int.fetchOne(db, sql: "select max(\"order\") from memory_span where memory_id = ?", arguments: [target.rawValue]) ?? -1) + 1
            let spans = try MemorySpan.filter(Column("memory_id") == source.rawValue).order(Column("order")).fetchAll(db)
            for (i, var span) in spans.enumerated() {
                span.memoryID = target
                span.order = next + i
                if i == 0 { span.titleText = span.titleText ?? sourceTitle; span.candidateID = span.candidateID ?? sourceCandidate }
                try span.insert(db)
            }
            try db.execute(sql: "insert or ignore into memory_person (memory_id, person_id, role_text) select ?, person_id, role_text from memory_person where memory_id = ?", arguments: [target.rawValue, source.rawValue])
            try db.execute(sql: "insert or ignore into memory_place (memory_id, place_id) select ?, place_id from memory_place where memory_id = ?", arguments: [target.rawValue, source.rawValue])
            try db.execute(sql: "update anchor set memory_id = ? where memory_id = ?", arguments: [target.rawValue, source.rawValue])
            let targetCollections = try Int.fetchOne(db, sql: "select count(*) from collection_memory where memory_id = ?", arguments: [target.rawValue]) ?? 0
            if targetCollections == 0 {
                try db.execute(sql: "insert or ignore into collection_memory (collection_id, memory_id) select collection_id, ? from collection_memory where memory_id = ?", arguments: [target.rawValue, source.rawValue])
            }
            let targetChapter = try String?.fetchOne(db, sql: "select chapter_id from memory where id = ?", arguments: [target.rawValue]) ?? nil
            if targetChapter == nil {
                try db.execute(sql: "update memory set chapter_id = (select chapter_id from memory where id = ?) where id = ?", arguments: [source.rawValue, target.rawValue])
            }
            _ = try Memory.deleteOne(db, key: source.rawValue)
        }
    }

    public func anchors(of memory: MemoryID) throws -> [Anchor] {
        try db.writer.read { try Anchor.filter(Column("memory_id") == memory.rawValue).fetchAll($0) }
    }

    public func allAnchors() throws -> [Anchor] {
        try db.writer.read { try Anchor.fetchAll($0) }
    }

    public func insertAnchor(_ anchor: Anchor) throws {
        try db.writer.write { try anchor.insert($0) }
    }

    public func insertPlace(_ place: MemoryPlace) throws {
        try db.writer.write { db in
            try db.execute(sql: "insert or ignore into memory_place (memory_id, place_id) values (?, ?)", arguments: [place.memoryID.rawValue, place.placeID.rawValue])
        }
    }

    public func update(_ anchor: Anchor) throws {
        try db.writer.write { try anchor.update($0) }
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

    /// Everyday browsing: every memory not hidden from the timeline.
    public func visibleMemories() throws -> [Memory] {
        try db.writer.read { try Memory.filter(Column("hidden_from_timeline") == false).order(Column("created_at")).fetchAll($0) }
    }

    public func excludedIDs() throws -> Set<MemoryID> {
        try db.writer.read { Set(try Memory.filter(Column("excluded_from_ai") == true).fetchAll($0).map(\.id)) }
    }

    public func setHidden(_ id: MemoryID, _ hidden: Bool) throws {
        try db.writer.write { try $0.execute(sql: "update memory set hidden_from_timeline = ? where id = ?", arguments: [hidden, id.rawValue]) }
    }

    public func setExcluded(_ id: MemoryID, _ excluded: Bool) throws {
        try db.writer.write { try $0.execute(sql: "update memory set excluded_from_ai = ? where id = ?", arguments: [excluded, id.rawValue]) }
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

    public func updateTitle(_ id: MemoryID, _ title: String) throws {
        try db.writer.write { try $0.execute(sql: "update memory set title = ? where id = ?", arguments: [title, id.rawValue]) }
    }

    public func unlink(_ person: PersonID, from memory: MemoryID) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from memory_person where memory_id = ? and person_id = ?", arguments: [memory.rawValue, person.rawValue])
        }
    }

    /// Links a person to a memory; a second link to the same person is a no-op.
    public func link(_ person: PersonID, to memory: MemoryID, roleText: String?) throws {
        try db.writer.write { db in
            try db.execute(sql: "insert or ignore into memory_person (memory_id, person_id, role_text) values (?, ?, ?)",
                           arguments: [memory.rawValue, person.rawValue, roleText])
        }
    }
}
