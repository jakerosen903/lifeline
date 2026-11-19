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
    /// can never leave an accepted memory behind a card that is still pending. The card's
    /// continuations are marked with it, and the memory joins its story, in that same
    /// transaction (M5): a kill never leaves a kept memory with its continuation cards still
    /// pending or its "Part of" line lost.
    public func insert(_ memory: Memory, spans: [MemorySpan], people: [MemoryPerson], places: [MemoryPlace], links: [MomentEntity] = [], entities: EntityRepository.Write = .init(), anchors: [Anchor],
                       acceptingCandidate candidate: CandidateID? = nil, acceptingContinuations continuations: [CandidateID] = [],
                       joiningStory story: (id: StoryID, chapterID: ChapterID?)? = nil) throws {
        guard !spans.isEmpty else { throw Error.noSpan }
        try db.writer.write { db in
            try memory.insert(db)
            for span in spans { try span.insert(db) }
            try EntityRepository.apply(entities, in: db)
            for person in people { try person.link.insertIgnoringDuplicate(db) }
            for place in places { try place.link.insertIgnoringDuplicate(db) }
            for link in links { try link.insertIgnoringDuplicate(db) }
            try EntityRepository.giveFirstTelling(toEntitiesOf: memory.id, span: spans[0], in: db)
            for anchor in anchors { try anchor.insert(db) }
            if let candidate {
                try db.execute(sql: "update candidate set status = ? where id = ?", arguments: [CandidateStatus.accepted.rawValue, candidate.rawValue])
                // Kept from a card, so told: a floating memory (no card) is not.
                try PhotoRepository.linkSubjectPhoto(ofSegment: spans[0].segmentID, to: memory.id, in: db)
            }
            try Self.accept(continuations, in: db)
            if let story {
                _ = try StoryRepository.join([memory.id], story: story.id, title: nil, chapterID: story.chapterID, newStoryID: story.id, in: db)
            }
        }
    }

    /// The cards that carried a telling on, marked accepted with it.
    static func accept(_ continuations: [CandidateID], in db: Database) throws {
        for id in continuations {
            try db.execute(sql: "update candidate set status = ? where id = ?", arguments: [CandidateStatus.accepted.rawValue, id.rawValue])
        }
    }

    /// Removes a memory and, by cascade, its spans, people, places and anchors.
    /// The memory and everything hanging off it (cascade). A story left with no member goes too,
    /// and so does an untitled chapter left with nothing in it.
    public func delete(_ id: MemoryID) throws {
        try db.writer.write { db in
            _ = try Memory.deleteOne(db, key: id.rawValue)
            try db.execute(sql: Self.deleteEmptyStoriesSQL)
            try db.execute(sql: ChapterRepository.deleteEmptyUntitledSQL)
        }
    }

    static let deleteEmptyStoriesSQL = "delete from story where not exists (select 1 from story_moment where story_moment.story_id = story.id)"

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

    /// Every told memory with a span in this session, once each, by its first span here (segment, then start).
    /// Unlike `memories(in:)`, a memory first told in an earlier session counts when a telling of this session
    /// was merged into it. Stand-ins are left out.
    public func memories(toldIn session: SessionID) throws -> [Memory] {
        try db.writer.read { db in
            try Memory.fetchAll(db, sql: """
                select memory.* from memory
                join (
                    select memory_span.memory_id, segment."index" as segment_index, memory_span.start_ms,
                           row_number() over (partition by memory_span.memory_id order by segment."index", memory_span.start_ms) as nth
                    from memory_span join segment on segment.id = memory_span.segment_id
                    where segment.session_id = ?
                ) here on here.memory_id = memory.id and here.nth = 1
                where memory.created_from_candidate_id is not null
                order by here.segment_index, here.start_ms, memory.created_at
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
            try Person.fetchAll(db, sql: Person.selectSQL + """
                join moment_entity me on me.entity_id = person.entity_id
                where me.memory_id = ? and me.relation = 'mention'
                order by entity.title
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

    /// The first telling (lowest `order`) of every told, visible memory of these kinds, with its
    /// session, in one query. A hidden memory or a floating stand-in is absent; so is a memory with no span.
    public func firstTellings(kinds: Set<MemoryKind>) throws -> [MemoryID: Telling] {
        guard !kinds.isEmpty else { return [:] }
        return try db.writer.read { db in
            let marks = databaseQuestionMarks(count: kinds.count)
            let rows = try Row.fetchAll(db, sql: """
                select span.memory_id, span.start_ms, span.end_ms, session.id as session_id, session.audio_path, session.started_at
                from (select memory_id, min("order") as first_order from memory_span group by memory_id) first
                join memory_span span on span.memory_id = first.memory_id and span."order" = first.first_order
                join memory on memory.id = span.memory_id
                join segment on segment.id = span.segment_id
                join session on session.id = segment.session_id
                where memory.kind in (\(marks)) and memory.hidden_from_timeline = 0 and memory.created_from_candidate_id is not null
                """, arguments: StatementArguments(kinds.map(\.rawValue)))
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                (MemoryID(rawValue: row["memory_id"]),
                 Telling(sessionID: SessionID(rawValue: row["session_id"]), audioPath: row["audio_path"],
                         range: MsRange(start: row["start_ms"], end: row["end_ms"]), toldAt: row["started_at"]))
            })
        }
    }

    /// Every telling recorded in this session, with its memory, in session order. Stand-ins
    /// are left out as in `memories(in:)`; a later span of any real memory counts.
    public func spans(in session: SessionID) throws -> [(Memory, MemorySpan)] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select memory.*, memory_span.memory_id as s_memory_id, memory_span.segment_id as s_segment_id, memory_span.start_ms as s_start_ms,
                       memory_span.end_ms as s_end_ms, memory_span."order" as s_order, memory_span.title_text as s_title_text, memory_span.candidate_id as s_candidate_id,
                       memory_span.continues_order as s_continues_order
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
                                      titleText: row["s_title_text"], candidateID: (row["s_candidate_id"] as String?).map(CandidateID.init(rawValue:)),
                                      continuesOrder: row["s_continues_order"])
                return (memory, span)
            }
        }
    }

    /// The memory a card made, if it was kept as its own (M5: no segment join, so a hint stored
    /// in a continuation's segment still finds it).
    public func memory(createdFrom candidate: CandidateID) throws -> Memory? {
        try db.writer.read { try Memory.filter(Column("created_from_candidate_id") == candidate.rawValue).fetchOne($0) }
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
        /// Every person, place, thing and idea it names or describes (M7: one link table).
        public var links: [MomentEntity]
        public var anchors: [Anchor]
        public var collectionIDs: [CollectionID]
        /// Pair decisions and story membership go with a memory on cascade; undo brings them back (M5).
        public var pairs: [DuplicatePair] = []
        public var story: StoryMoment? = nil
        public var storyTitle: String? = nil
        public var takenAt: Date
    }

    public func snapshot(of id: MemoryID) throws -> Snapshot? {
        try db.writer.read { db in
            guard let memory = try Memory.fetchOne(db, key: id.rawValue) else { return nil }
            return Snapshot(
                memory: memory,
                spans: try MemorySpan.filter(Column("memory_id") == id.rawValue).order(Column("order")).fetchAll(db),
                links: try MomentEntity.filter(Column("memory_id") == id.rawValue).fetchAll(db),
                anchors: try Anchor.filter(Column("memory_id") == id.rawValue).fetchAll(db),
                collectionIDs: try String.fetchAll(db, sql: "select collection_id from collection_memory where memory_id = ?", arguments: [id.rawValue]).map(CollectionID.init(rawValue:)),
                pairs: try DuplicatePair.filter(Column("a_memory_id") == id.rawValue || Column("b_memory_id") == id.rawValue).fetchAll(db),
                story: try StoryMoment.filter(Column("memory_id") == id.rawValue).fetchOne(db),
                storyTitle: try String?.fetchOne(db, sql: "select story.title from story join story_moment sm on sm.story_id = story.id where sm.memory_id = ?", arguments: [id.rawValue]) ?? nil,
                takenAt: .now)
        }
    }

    /// Puts the memory back exactly as the snapshot has it, re-creating the row if it was deleted.
    public func restore(_ snapshot: Snapshot) throws {
        try restore([snapshot], settingCandidate: nil)
    }

    /// Several memories back at once, a card's status with them, a pair row reopened and a photo link a merge added removed, in
    /// one transaction: an undo that is cut short leaves nothing half done.
    public func restore(_ snapshots: [Snapshot], settingCandidate candidate: (id: CandidateID, status: CandidateStatus)?,
                        reopeningPair pair: DuplicatePair? = nil, removingPhoto photo: (id: PhotoID, from: MemoryID)? = nil) throws {
        try db.writer.write { db in
            // The link a merge added goes in the same write; the photo row stays (its session still points at it).
            if let photo { _ = try PhotoRepository.removeLink(photo.id, from: .memory(photo.from), in: db) }
            // Every memory row first, so a pair between two restored memories finds both.
            for snapshot in snapshots { try Self.restorable(snapshot.memory, in: db).save(db) }
            for snapshot in snapshots { try Self.restore(snapshot, in: db) }
            if let candidate {
                try db.execute(sql: "update candidate set status = ? where id = ?", arguments: [candidate.status.rawValue, candidate.id.rawValue])
            }
            if let pair {
                // The merge took the row with the folded memory; a snapshot may already have put it back.
                try db.execute(sql: """
                    insert or ignore into duplicate_pair (id, a_memory_id, b_memory_id, score, verdict, status, decided_at) values (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [pair.id.rawValue, pair.aMemoryID.rawValue, pair.bMemoryID.rawValue, pair.score, pair.verdict.rawValue, PairStatus.open.rawValue, nil])
                try db.execute(sql: "update duplicate_pair set status = ?, decided_at = null where id = ?", arguments: [PairStatus.open.rawValue, pair.id.rawValue])
            }
        }
    }

    /// The memory as the snapshot has it, with no chapter when that chapter was removed since:
    /// its tag cannot point at a row that is gone.
    private static func restorable(_ memory: Memory, in db: Database) throws -> Memory {
        guard let chapter = memory.chapterID, try !Chapter.exists(db, key: chapter.rawValue) else { return memory }
        var freed = memory
        freed.chapterID = nil
        return freed
    }

    private static func restore(_ snapshot: Snapshot, in db: Database) throws {
            let id = snapshot.memory.id.rawValue
            try restorable(snapshot.memory, in: db).save(db)
            for table in ["memory_span", "moment_entity", "anchor", "collection_memory"] {
                try db.execute(sql: "delete from \(table) where memory_id = ?", arguments: [id])
            }
            for span in snapshot.spans { try span.insert(db) }
            // An entity deleted since the snapshot stays deleted; its link does not come back.
            for link in snapshot.links where try Entity.exists(db, key: link.entityID.rawValue) { try link.insertIgnoringDuplicate(db) }
            for anchor in snapshot.anchors { try anchor.insert(db) }
            for collection in snapshot.collectionIDs {
                try db.execute(sql: "insert or ignore into collection_memory (collection_id, memory_id) values (?, ?)", arguments: [collection.rawValue, id])
            }
            for pair in snapshot.pairs
            where try Memory.exists(db, key: pair.aMemoryID.rawValue) && Memory.exists(db, key: pair.bMemoryID.rawValue) {
                try db.execute(sql: """
                    insert or ignore into duplicate_pair (id, a_memory_id, b_memory_id, score, verdict, status, decided_at) values (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [pair.id.rawValue, pair.aMemoryID.rawValue, pair.bMemoryID.rawValue, pair.score, pair.verdict.rawValue, pair.status.rawValue, pair.decidedAt])
            }
            if let moment = snapshot.story {
                // The story may have gone when this was its last member; it comes back untitled.
                if try !Story.exists(db, key: moment.storyID.rawValue) {
                    try Story(id: moment.storyID, title: snapshot.storyTitle, chapterID: nil, createdAt: .now).insert(db)
                }
                try db.execute(sql: "delete from story_moment where memory_id = ?", arguments: [id])
                try moment.insert(db)
            }
    }

    /// "Same story" on a card, in one transaction: the span, its edges, the card marked accepted.
    /// `promotingStandIn` carries the card's title, quote and candidate when the target is a
    /// resolver stand-in: its borrowed span goes, this telling becomes order 0 and the memory
    /// becomes real. A failure anywhere leaves the card pending and the target untouched.
    /// Returns the session's photo when this write linked it to the target (see `PhotoRepository.linkSubjectPhoto`).
    @discardableResult
    public func mergeSpan(_ span: MemorySpan, continuations: [MemorySpan] = [], people: [MemoryPerson], places: [MemoryPlace], links: [MomentEntity] = [], entities: EntityRepository.Write = .init(), anchors: [Anchor],
                          promotingStandIn: (title: String, summaryQuote: String)?, acceptingCandidate candidate: CandidateID,
                          acceptingContinuations continuationCards: [CandidateID] = []) throws -> PhotoID? {
        try db.writer.write { db in
            try Self.mergeSpan(span, continuations: continuations, people: people, places: places, links: links, entities: entities, anchors: anchors,
                               promotingStandIn: promotingStandIn, acceptingCandidate: candidate, acceptingContinuations: continuationCards, in: db)
        }
    }

    static func mergeSpan(_ span: MemorySpan, continuations: [MemorySpan], people: [MemoryPerson], places: [MemoryPlace], links: [MomentEntity] = [], entities: EntityRepository.Write = .init(), anchors: [Anchor],
                          promotingStandIn: (title: String, summaryQuote: String)?, acceptingCandidate candidate: CandidateID,
                          acceptingContinuations continuationCards: [CandidateID] = [], in db: Database) throws -> PhotoID? {
            var span = span
            if let promoted = promotingStandIn {
                try db.execute(sql: "delete from memory_span where memory_id = ?", arguments: [span.memoryID.rawValue])
                span.order = 0
                try db.execute(sql: "update memory set title = ?, summary_quote = ?, created_from_candidate_id = ? where id = ?",
                               arguments: [promoted.title, promoted.summaryQuote, candidate.rawValue, span.memoryID.rawValue])
            }
            try span.insert(db)
            // The card's other segments follow as spans that carry on this telling (M5).
            for (i, var extra) in continuations.enumerated() {
                extra.memoryID = span.memoryID
                extra.order = span.order + 1 + i
                extra.continuesOrder = span.order
                try extra.insert(db)
            }
            try EntityRepository.apply(entities, in: db)
            for person in people { try person.link.insertIgnoringDuplicate(db) }
            for place in places { try place.link.insertIgnoringDuplicate(db) }
            for link in links { try link.insertIgnoringDuplicate(db) }
            try EntityRepository.giveFirstTelling(toEntitiesOf: span.memoryID, span: span, in: db)
            for anchor in anchors { try anchor.insert(db) }
            try db.execute(sql: "update candidate set status = ? where id = ?", arguments: [CandidateStatus.accepted.rawValue, candidate.rawValue])
            try Self.accept(continuationCards, in: db)
            return try PhotoRepository.linkSubjectPhoto(ofSegment: span.segmentID, to: span.memoryID, in: db)
    }

    /// A group (M5): every source folds into the target, oldest first as given, then the card
    /// joins as the last telling. One transaction: a failure anywhere leaves every memory as it was.
    /// Returns the session's photo when this write linked it to the target. The check runs after the folds, so a
    /// photo a folded memory carried to the target is not counted as added.
    @discardableResult
    public func mergeGroup(sources: [Memory], into target: Memory, span: MemorySpan, continuations: [MemorySpan], people: [MemoryPerson],
                           places: [MemoryPlace], links: [MomentEntity] = [], entities: EntityRepository.Write = .init(), anchors: [Anchor], promotingStandIn: (title: String, summaryQuote: String)?,
                           acceptingCandidate candidate: CandidateID, acceptingContinuations continuationCards: [CandidateID] = []) throws -> PhotoID? {
        try db.writer.write { db in
            for source in sources {
                guard let current = try Memory.fetchOne(db, key: target.id.rawValue) else { throw Error.noSpan }
                try Self.fold(source, into: current, in: db)
            }
            var last = span
            last.order = (try Int.fetchOne(db, sql: "select max(\"order\") from memory_span where memory_id = ?", arguments: [target.id.rawValue]) ?? -1) + 1
            return try Self.mergeSpan(last, continuations: continuations, people: people, places: places, links: links, entities: entities, anchors: anchors,
                               promotingStandIn: promotingStandIn, acceptingCandidate: candidate, acceptingContinuations: continuationCards, in: db)
        }
    }

    /// "Separate this telling" (M5): the span with `order`, and every span that carries it on,
    /// move to `new` as orders 0…; the rest of the memory is renumbered, continuation links
    /// following through the same map. One transaction. Edges move in `MergeActions`.
    /// The edges that leave with a separated telling.
    public struct MovingEdges: Sendable, Equatable {
        public var anchors: [AnchorID]
        public var people: [PersonID]
        public var places: [PlaceID]
        public init(anchors: [AnchorID], people: [PersonID], places: [PlaceID]) { self.anchors = anchors; self.people = people; self.places = places }
    }

    public func separate(_ memory: MemoryID, order: Int, into new: Memory, moving: MovingEdges, clearRange: Bool) throws {
        try db.writer.write { db in
            let spans = try MemorySpan.filter(Column("memory_id") == memory.rawValue).order(Column("order")).fetchAll(db)
            guard spans.contains(where: { $0.order == order }) else { throw Error.noSpan }
            try new.insert(db)
            let movingSpans = spans.filter { $0.order == order || $0.continuesOrder == order }
            let staying = spans.filter { span in !movingSpans.contains(where: { $0.order == span.order }) }
            try db.execute(sql: "delete from memory_span where memory_id = ?", arguments: [memory.rawValue])
            for (i, var span) in movingSpans.enumerated() {
                span.memoryID = new.id
                span.order = i
                span.continuesOrder = i == 0 ? nil : 0
                try span.insert(db)
            }
            let renumbered = Dictionary(uniqueKeysWithValues: staying.enumerated().map { ($1.order, $0) })
            for (i, var span) in staying.enumerated() {
                span.order = i
                span.continuesOrder = span.continuesOrder.flatMap { renumbered[$0] }
                try span.insert(db)
            }
            for anchor in moving.anchors {
                guard try Anchor.exists(db, key: anchor.rawValue) else { throw Error.noSpan }
                try db.execute(sql: "update anchor set memory_id = ? where id = ?", arguments: [new.id.rawValue, anchor.rawValue])
            }
            // A link moves with its role text ("my sister"); a role the person typed is theirs to keep.
            for entity in moving.people.map(\.rawValue) + moving.places.map(\.rawValue) {
                try db.execute(sql: """
                    insert or ignore into moment_entity (memory_id, entity_id, relation, role_text)
                    select ?, entity_id, relation, role_text from moment_entity where memory_id = ? and entity_id = ?
                    """, arguments: [new.id.rawValue, memory.rawValue, entity])
                try db.execute(sql: "delete from moment_entity where memory_id = ? and entity_id = ?", arguments: [memory.rawValue, entity])
            }
            if clearRange {
                try db.execute(sql: "update memory set earliest = null, latest = null, likely_start = null, likely_end = null, granularity = null, origin = null, evidence_text = null where id = ?",
                               arguments: [memory.rawValue])
            }
        }
    }

    /// "Which part of the recording" (M6): one span's bounds move within its segment. The span's
    /// segment, order and continuation link never change. Refused when the span is missing.
    public func retime(_ memory: MemoryID, order: Int, startMs: Milliseconds, endMs: Milliseconds,
                       rewritingCard card: (id: CandidateID, payload: String)? = nil) throws {
        try db.writer.write { db in
            guard try MemorySpan.filter(Column("memory_id") == memory.rawValue && Column("order") == order).fetchOne(db) != nil else { throw Error.noSpan }
            try db.execute(sql: "update memory_span set start_ms = ?, end_ms = ? where memory_id = ? and \"order\" = ?",
                           arguments: [startMs, endMs, memory.rawValue, order])
            // The card that made the telling follows in the same write, so the two never disagree.
            if let card { try db.execute(sql: "update candidate set payload = ? where id = ?", arguments: [card.payload, card.id.rawValue]) }
        }
    }

    /// Moves an anchor to another memory.
    public func move(anchor: AnchorID, to memory: MemoryID) throws {
        try db.writer.write { try $0.execute(sql: "update anchor set memory_id = ? where id = ?", arguments: [memory.rawValue, anchor.rawValue]) }
    }

    public func unlinkPlace(_ place: PlaceID, from memory: MemoryID) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from moment_entity where memory_id = ? and entity_id = ? and relation = 'mention'", arguments: [memory.rawValue, place.rawValue])
        }
    }

    /// Re-points every edge of `source` at `target` and appends its spans after the target's.
    /// Collections and the chapter move only when the target has none; the range moves when
    /// the target has none. A stand-in target becomes real: its borrowed span goes and the
    /// source's first telling, title, quote and candidate become the target's. One transaction;
    /// the source row is deleted at the end.
    public func fold(_ source: Memory, into target: Memory) throws {
        try db.writer.write { db in try Self.fold(source, into: target, in: db) }
    }

    static func fold(_ source: Memory, into target: Memory, in db: Database) throws {
            var next = (try Int.fetchOne(db, sql: "select max(\"order\") from memory_span where memory_id = ?", arguments: [target.id.rawValue]) ?? -1) + 1
            if target.isFloating {
                try db.execute(sql: "delete from memory_span where memory_id = ?", arguments: [target.id.rawValue])
                try db.execute(sql: "update memory set title = ?, summary_quote = ?, created_from_candidate_id = ? where id = ?",
                               arguments: [source.title, source.summaryQuote, source.createdFromCandidateID?.rawValue, target.id.rawValue])
                next = 0
            }
            let spans = try MemorySpan.filter(Column("memory_id") == source.id.rawValue).order(Column("order")).fetchAll(db)
            for (i, var span) in spans.enumerated() {
                span.memoryID = target.id
                span.order = next + i
                span.continuesOrder = span.continuesOrder.map { $0 + next }
                if i == 0, !target.isFloating { span.titleText = span.titleText ?? source.title; span.candidateID = span.candidateID ?? source.createdFromCandidateID }
                try span.insert(db)
            }
            if !target.range.isPlaced, source.range.isPlaced {
                var moved = target
                moved.range = source.range
                try moved.update(db, columns: ["earliest", "latest", "likely_start", "likely_end", "granularity", "origin", "evidence_text"])
            }
            try db.execute(sql: """
                insert or ignore into moment_entity (memory_id, entity_id, relation, role_text)
                select ?, entity_id, relation, role_text from moment_entity where memory_id = ?
                """, arguments: [target.id.rawValue, source.id.rawValue])
            try db.execute(sql: "update anchor set memory_id = ? where memory_id = ?", arguments: [target.id.rawValue, source.id.rawValue])
            let targetCollections = try Int.fetchOne(db, sql: "select count(*) from collection_memory where memory_id = ?", arguments: [target.id.rawValue]) ?? 0
            if targetCollections == 0 {
                try db.execute(sql: "insert or ignore into collection_memory (collection_id, memory_id) select collection_id, ? from collection_memory where memory_id = ?", arguments: [target.id.rawValue, source.id.rawValue])
            }
            if target.chapterID == nil {
                try db.execute(sql: "update memory set chapter_id = (select chapter_id from memory where id = ?) where id = ?", arguments: [source.id.rawValue, target.id.rawValue])
            }
            try Self.movePhotoLinks(from: source.id, to: target.id, in: db)
            _ = try Memory.deleteOne(db, key: source.id.rawValue)
            try db.execute(sql: Self.deleteEmptyStoriesSQL)
    }

    /// The source's photos the target does not hold move to the target, after its own. The target keeps
    /// its cover, so a source cover arrives as an attached photo; with no cover on the target it stays one.
    private static func movePhotoLinks(from source: MemoryID, to target: MemoryID, in db: Database) throws {
        var hasCover = try Int.fetchOne(db, sql: "select count(*) from photo_link where memory_id = ? and role = 'cover'", arguments: [target.rawValue]) == 1
        var next = (try Int.fetchOne(db, sql: "select max(sort_order) from photo_link where memory_id = ?", arguments: [target.rawValue]) ?? -1) + 1
        let moving = try Row.fetchAll(db, sql: """
            select photo_id, role from photo_link where memory_id = ?
              and photo_id not in (select photo_id from photo_link where memory_id = ?)
            order by role = 'cover' desc, sort_order, rowid
            """, arguments: [source.rawValue, target.rawValue])
        for row in moving {
            let role: PhotoRole = hasCover ? .attached : .cover
            try db.execute(sql: "insert into photo_link (photo_id, memory_id, role, sort_order) values (?, ?, ?, ?)",
                           arguments: [row["photo_id"] as String, target.rawValue, role.rawValue, next])
            hasCover = true
            next += 1
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
        try db.writer.write { try place.link.insertIgnoringDuplicate($0) }
    }

    public func update(_ anchor: Anchor) throws {
        try db.writer.write { try anchor.update($0) }
    }

    public func places(of memory: MemoryID) throws -> [Place] {
        try db.writer.read { db in
            try Entity.fetchAll(db, sql: """
                select entity.* from entity join moment_entity me on me.entity_id = entity.id
                where me.memory_id = ? and me.relation = 'mention' and entity.type = 'place' order by entity.title
                """, arguments: [memory.rawValue]).map(Place.init)
        }
    }

    public func updateRange(_ id: MemoryID, _ range: TimeRange) throws {
        try db.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id.rawValue) else { return }
            memory.range = range
            try memory.update(db)
        }
    }

    /// The memory's range, in one write. A chapter's range holds stated years only (S6c), so no chapter changes with it.
    /// With a range in `ifCurrently`, the write happens only while the stored range is still that one: an offer drawn against
    /// an older range must not replace a newer one. Returns false when the memory is gone or its range has changed.
    @discardableResult
    public func updateRange(_ id: MemoryID, _ range: TimeRange, ifCurrently expected: TimeRange?) throws -> Bool {
        try db.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id.rawValue) else { return false }
            if let expected, memory.range != expected { return false }
            memory.range = range
            try memory.update(db)
            return true
        }
    }

    /// One range to write, checked against the range the caller saw.
    public struct RangeChange: Sendable, Equatable {
        public var memory: MemoryID
        public var range: TimeRange
        public var ifCurrently: TimeRange
        public init(memory: MemoryID, range: TimeRange, ifCurrently: TimeRange) {
            self.memory = memory; self.range = range; self.ifCurrently = ifCurrently
        }
    }

    /// One write. Each change happens only while the stored range equals `ifCurrently`. The memory's chapter does not change (S6c).
    /// Returns the memories it changed, in the order given. A memory that is gone is skipped.
    @discardableResult
    public func updateRanges(_ changes: [RangeChange]) throws -> [MemoryID] {
        guard !changes.isEmpty else { return [] }  // no transaction for no work
        return try db.writer.write { db in
            var changed: [MemoryID] = []
            for change in changes {
                guard var memory = try Memory.fetchOne(db, key: change.memory.rawValue), memory.range == change.ifCurrently else { continue }
                memory.range = change.range
                try memory.update(db)
                changed.append(change.memory)
            }
            return changed
        }
    }

    public func allMemories() throws -> [Memory] {
        try db.writer.read { try Memory.order(Column("created_at")).fetchAll($0) }
    }

    /// Everyday browsing: every memory not hidden from the timeline.
    public func visibleMemories() throws -> [Memory] {
        try db.writer.read { try Memory.filter(Column("hidden_from_timeline") == false).order(Column("created_at")).fetchAll($0) }
    }

    /// The words of each telling of each told, visible memory, as said, joined with one space, first telling first, in one statement.
    /// Only words inside a span count: the segment's other words are not the memory's. A span with no word rows adds nothing,
    /// and a continuation span is a telling of its own.
    public func tellingWords() throws -> [MemoryID: [String]] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select ms.memory_id, ms."order", w.text
                from memory_span ms
                join memory m on m.id = ms.memory_id
                join word w on w.segment_id = ms.segment_id and w.start_ms >= ms.start_ms and w.end_ms <= ms.end_ms
                where m.hidden_from_timeline = 0 and m.created_from_candidate_id is not null
                order by ms.memory_id, ms."order", w."index"
                """)
            var out: [MemoryID: [String]] = [:]
            var current: (memory: String, order: Int, words: [String])?
            func flush() {
                guard let current else { return }
                out[MemoryID(rawValue: current.memory), default: []].append(current.words.joined(separator: " "))
            }
            for row in rows {
                let memory: String = row["memory_id"], order: Int = row["order"], text: String = row["text"]
                if let held = current, held.memory == memory, held.order == order {
                    current?.words.append(text)
                } else {
                    flush()
                    current = (memory, order, [text])
                }
            }
            flush()
            return out
        }
    }

    public func excludedIDs() throws -> Set<MemoryID> {
        try db.writer.read { Set(try Memory.filter(Column("excluded_from_ai") == true).fetchAll($0).map(\.id)) }
    }

    /// The segments of a session that hold a span of a memory excluded from AI. Their words never go to the interviewer.
    public func excludedSegmentIDs(in session: SessionID) throws -> Set<SegmentID> {
        try db.writer.read { db in
            let ids = try String.fetchAll(db, sql: """
                select distinct memory_span.segment_id
                from memory_span
                join memory on memory.id = memory_span.memory_id
                join segment on segment.id = memory_span.segment_id
                where segment.session_id = ? and memory.excluded_from_ai = 1
                """, arguments: [session.rawValue])
            return Set(ids.map(SegmentID.init(rawValue:)))
        }
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

    /// The moments of a chapter: what its rows show and its range spans. A fact, feeling or goal
    /// keeps its `chapter_id` but leaves both (M7).
    public func moments(inChapter chapter: ChapterID) throws -> [Memory] {
        try memories(inChapter: chapter).filter(\.isMoment)
    }

    /// The About section: facts, feelings and goals, oldest first. Stand-ins are never here.
    public func aboutMemories(includingHidden: Bool) throws -> [Memory] {
        try (includingHidden ? allMemories() : visibleMemories()).filter { !$0.isMoment && !$0.isFloating }
    }

    /// The kind, the detail links and the story place in one write, so a kill between them
    /// leaves nothing half changed (M7). A chapter's range holds stated years only and does not move.
    /// The receipt holds what the change took away (a story place, detail links) for `undoKind`.
    @discardableResult
    public func setKind(_ id: MemoryID, _ kind: MemoryKind) throws -> KindReceipt {
        try db.writer.write { db in
            let from = try MemoryKind(rawValue: String.fetchOne(db, sql: "select kind from memory where id = ?", arguments: [id.rawValue]) ?? "") ?? .event
            var receipt = KindReceipt(memory: id, from: from, to: kind, story: nil, details: [])
            try db.execute(sql: "update memory set kind = ? where id = ?", arguments: [kind.rawValue, id.rawValue])
            if kind.isMoment {
                // A moment names what it was about; it is no longer a standing statement (M7).
                let rows = try MomentEntity.filter(Column("memory_id") == id.rawValue).fetchAll(db)
                receipt.details = rows.filter { $0.relation == .detail }.map(\.entityID)
                receipt.alsoMentioned = Set(rows.filter { $0.relation == .mention }.map(\.entityID)).intersection(receipt.details)
                try db.execute(sql: """
                    insert or ignore into moment_entity (memory_id, entity_id, relation, role_text)
                    select memory_id, entity_id, 'mention', role_text from moment_entity where memory_id = ? and relation = 'detail'
                    """, arguments: [id.rawValue])
                try db.execute(sql: "delete from moment_entity where memory_id = ? and relation = 'detail'", arguments: [id.rawValue])
            } else {
                // Stories are for scenes. The place is remembered so an undo can give it back.
                if let moment = try StoryMoment.filter(Column("memory_id") == id.rawValue).fetchOne(db),
                   let story = try Story.fetchOne(db, key: moment.storyID.rawValue) {
                    receipt.story = StoryRepository.Membership(moment: moment, title: story.title, chapterID: story.chapterID)
                }
                try db.execute(sql: "delete from story_moment where memory_id = ?", arguments: [id.rawValue])
                try db.execute(sql: Self.deleteEmptyStoriesSQL)
            }
            return receipt
        }
    }

    /// Puts a kind change back, in one write: the kind, the detail links a
    /// moment turned into mentions, and the story place a fact, feeling or goal gave up (with
    /// the story itself when it was deleted for being empty). Stale once the kind moved again.
    public func undoKind(_ receipt: KindReceipt) throws {
        try db.writer.write { db in
            guard try String.fetchOne(db, sql: "select kind from memory where id = ?", arguments: [receipt.memory.rawValue]) == receipt.to.rawValue else {
                throw CandidateActions.Error.stale
            }
            try db.execute(sql: "update memory set kind = ? where id = ?", arguments: [receipt.from.rawValue, receipt.memory.rawValue])
            for entity in receipt.details {
                if receipt.alsoMentioned.contains(entity) {
                    try db.execute(sql: """
                        insert or ignore into moment_entity (memory_id, entity_id, relation, role_text)
                        select memory_id, entity_id, 'detail', role_text from moment_entity where memory_id = ? and entity_id = ? and relation = 'mention'
                        """, arguments: [receipt.memory.rawValue, entity.rawValue])
                } else {
                    try db.execute(sql: "update moment_entity set relation = 'detail' where memory_id = ? and entity_id = ? and relation = 'mention'",
                                   arguments: [receipt.memory.rawValue, entity.rawValue])
                }
            }
            if let membership = receipt.story {
                if try !Story.exists(db, key: membership.moment.storyID.rawValue) {
                    try Story(id: membership.moment.storyID, title: membership.title, chapterID: membership.chapterID, createdAt: .now).insert(db)
                }
                try db.execute(sql: "delete from story_moment where memory_id = ?", arguments: [receipt.memory.rawValue])
                try membership.moment.insert(db)
            }
        }
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
            try db.execute(sql: "delete from moment_entity where memory_id = ? and entity_id = ? and relation = 'mention'", arguments: [memory.rawValue, person.rawValue])
        }
    }

    /// Links a person to a memory; a second link to the same person is a no-op.
    public func link(_ person: PersonID, to memory: MemoryID, roleText: String?) throws {
        try db.writer.write { db in
            try MemoryPerson(memoryID: memory, personID: person, roleText: roleText).link.insertIgnoringDuplicate(db)
        }
    }
}
