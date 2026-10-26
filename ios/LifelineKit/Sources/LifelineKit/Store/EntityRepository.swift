import Foundation
import GRDB

/// People, places, things and ideas, and the one table that links them to memories (M7).
/// Titles match ignoring case and outer whitespace, never spelling.
public struct EntityRepository: Sendable {
    public enum Error: Swift.Error, Equatable {
        case emptyTitle
    }

    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    // MARK: - Entities

    /// Reuses an entity of the same type and title, so naming a thing twice links one thing.
    @discardableResult
    public func insert(type: EntityType, title: String, candidate: CandidateID? = nil, id: EntityID = .init()) throws -> Entity {
        try db.writer.write { db in try Self.insert(type: type, title: title, candidate: candidate, id: id, in: db) }
    }

    static func insert(type: EntityType, title: String, candidate: CandidateID?, id: EntityID, in db: Database) throws -> Entity {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.emptyTitle }
        if type != .person, let existing = try find(type: type, title: trimmed, in: db) { return existing }
        let entity = Entity(id: id, type: type, title: trimmed, createdFromCandidateID: candidate)
        try entity.insert(db)
        return entity
    }

    public func entity(id: EntityID) throws -> Entity? {
        try db.writer.read { try Entity.fetchOne($0, key: id.rawValue) }
    }

    /// One type, by title; hidden ones only when asked.
    public func entities(type: EntityType, includingHidden: Bool = false) throws -> [Entity] {
        try db.writer.read { db in
            var request = Entity.filter(Column("type") == type.rawValue)
            if !includingHidden { request = request.filter(Column("hidden_from_timeline") == false) }
            return try request.order(Column("title").collating(.nocase)).fetchAll(db)
        }
    }

    public func find(type: EntityType, title: String) throws -> Entity? {
        try db.writer.read { try Self.find(type: type, title: title, in: $0) }
    }

    static func find(type: EntityType, title: String, in db: Database) throws -> Entity? {
        let needle = PeopleRepository.normalize(title)
        guard !needle.isEmpty else { return nil }
        return try Entity.fetchOne(db, sql: "select * from entity where type = ? and lower(trim(title)) = ? order by created_at limit 1",
                                   arguments: [type.rawValue, needle])
    }

    public func rename(_ id: EntityID, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.emptyTitle }
        try db.writer.write { try $0.execute(sql: "update entity set title = ? where id = ?", arguments: [trimmed, id.rawValue]) }
    }

    /// The entity and its links go; the memories stay.
    public func delete(_ id: EntityID) throws {
        try db.writer.write { db in
            _ = try Entity.deleteOne(db, key: id.rawValue)
            try db.execute(sql: "delete from domain_tag where element_kind = ? and element_id = ?", arguments: [ElementKind.entity.rawValue, id.rawValue])
        }
    }

    public func setHidden(_ id: EntityID, _ hidden: Bool) throws {
        try db.writer.write { try $0.execute(sql: "update entity set hidden_from_timeline = ? where id = ?", arguments: [hidden, id.rawValue]) }
    }

    public func setExcluded(_ id: EntityID, _ excluded: Bool) throws {
        try db.writer.write { try $0.execute(sql: "update entity set excluded_from_ai = ? where id = ?", arguments: [excluded, id.rawValue]) }
    }

    // MARK: - One write

    /// Everything a Keep does to entities, worked out first and written in one transaction (M7):
    /// new entities (and a new person's row), links, first tellings, tags, and the card's status.
    /// A kill can never leave an entity without its link or a card pending behind its entity.
    public struct Write: Sendable {
        public var entities: [Entity] = []
        public var persons: [Person] = []
        public var links: [MomentEntity] = []
        public var spans: [EntitySpan] = []
        public var tags: [EntityTag] = []
        public var acceptingCandidate: CandidateID?

        public init() {}

        /// A planned entity of this type and title, so one Keep never plans the same thing twice.
        /// Within one plan the same words name the same entity, except two ideas under the dated
        /// default title, which are two ideas.
        func planned(_ type: EntityType, _ title: String) -> Entity? {
            if type == .idea, IdeaTitle.isDefault(title) { return nil }
            return entities.first { $0.type == type && PeopleRepository.normalize($0.title) == PeopleRepository.normalize(title) }
        }

        /// The union with another plan; an entity both planned keeps this plan's id.
        mutating func merge(_ other: Write) -> [EntityID: EntityID] {
            var remap: [EntityID: EntityID] = [:]
            for entity in other.entities {
                if let mine = planned(entity.type, entity.title) { remap[entity.id] = mine.id } else { entities.append(entity) }
            }
            persons += other.persons.filter { p in !persons.contains { $0.id == p.id } }
            links += other.links.map { var l = $0; l.entityID = remap[l.entityID] ?? l.entityID; return l }
            spans += other.spans.map { var s = $0; s.entityID = remap[s.entityID] ?? s.entityID; return s }
            tags += other.tags.map { EntityTag(entityID: remap[$0.entityID] ?? $0.entityID, text: $0.text) }
            return remap
        }
    }

    public struct EntityTag: Sendable, Equatable {
        public var entityID: EntityID
        public var text: String
        public init(entityID: EntityID, text: String) { self.entityID = entityID; self.text = text }
    }

    public func apply(_ write: Write) throws {
        try db.writer.write { try Self.apply(write, in: $0) }
    }

    static func apply(_ write: Write, in db: Database) throws {
        for entity in write.entities where try !Entity.exists(db, key: entity.id.rawValue) { try entity.insert(db) }
        for person in write.persons where try !Person.exists(db, key: person.id.rawValue) {
            try person.insert(db)
            try PeopleRepository.insertAlias(person.displayName, person.id, db)
        }
        for link in write.links { try link.insertIgnoringDuplicate(db) }
        for span in write.spans { try span.insertIgnoringDuplicate(db) }
        for tag in write.tags { try DomainTagRepository.tag(.entity, tag.entityID.rawValue, tag.text, in: db) }
        if let candidate = write.acceptingCandidate {
            try db.execute(sql: "update candidate set status = ? where id = ?", arguments: [CandidateStatus.accepted.rawValue, candidate.rawValue])
        }
    }

    /// Every entity linked to a memory that has no first telling yet takes this span, in the
    /// caller's transaction (Principle 9: a page can always play its first telling).
    static func giveFirstTelling(toEntitiesOf memory: MemoryID, span: MemorySpan, in db: Database) throws {
        try db.execute(sql: """
            insert or ignore into entity_span (entity_id, segment_id, start_ms, end_ms, "order")
            select entity_id, ?, ?, ?, 0 from moment_entity where memory_id = ?
            """, arguments: [span.segmentID.rawValue, span.startMs, span.endMs, memory.rawValue])
    }

    // MARK: - Links

    /// One link per memory, entity and relation; a second is a no-op that keeps the first role text.
    public func link(_ memory: MemoryID, _ entity: EntityID, relation: EntityRelation, roleText: String? = nil) throws {
        try db.writer.write { try MomentEntity(memoryID: memory, entityID: entity, relation: relation, roleText: roleText).insertIgnoringDuplicate($0) }
    }

    /// A detail leaves every entity it was on and lands on `entity` (nil: none), in one write.
    public func moveDetail(_ memory: MemoryID, to entity: EntityID?) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from moment_entity where memory_id = ? and relation = 'detail'", arguments: [memory.rawValue])
            if let entity { try MomentEntity(memoryID: memory, entityID: entity, relation: .detail).insertIgnoringDuplicate(db) }
        }
    }

    public func unlink(_ memory: MemoryID, _ entity: EntityID, relation: EntityRelation) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from moment_entity where memory_id = ? and entity_id = ? and relation = ?",
                           arguments: [memory.rawValue, entity.rawValue, relation.rawValue])
        }
    }

    /// Everything a memory names or describes, entities by title.
    public func links(of memory: MemoryID) throws -> [(entity: Entity, link: MomentEntity)] {
        try db.writer.read { db in
            let links = try MomentEntity.filter(Column("memory_id") == memory.rawValue).fetchAll(db)
            return try links.compactMap { link in try Entity.fetchOne(db, key: link.entityID.rawValue).map { (entity: $0, link: link) } }
                .sorted { $0.entity.title.localizedCaseInsensitiveCompare($1.entity.title) == .orderedAscending }
        }
    }

    /// The standing statements about an entity, oldest first.
    public func details(of entity: EntityID) throws -> [Memory] { try memories(of: entity, relation: .detail) }

    /// The moments an entity appears in, oldest first.
    public func moments(of entity: EntityID) throws -> [Memory] { try memories(of: entity, relation: .mention) }

    private func memories(of entity: EntityID, relation: EntityRelation) throws -> [Memory] {
        try db.writer.read { db in
            try Memory.fetchAll(db, sql: """
                select memory.* from memory join moment_entity me on me.memory_id = memory.id
                where me.entity_id = ? and me.relation = ? order by memory.created_at, memory.id
                """, arguments: [entity.rawValue, relation.rawValue])
        }
    }

    /// Every link to an entity, for merge, separate and curiosity.
    public func links(to entity: EntityID) throws -> [MomentEntity] {
        try db.writer.read { try MomentEntity.filter(Column("entity_id") == entity.rawValue).fetchAll($0) }
    }

    public func allLinks() throws -> [MomentEntity] {
        try db.writer.read { try MomentEntity.fetchAll($0) }
    }

    public func allEntities() throws -> [Entity] {
        try db.writer.read { try Entity.order(Column("created_at")).fetchAll($0) }
    }

    // MARK: - Spans

    /// Derived, never asked: the earliest and latest of everything linked, moments and details
    /// alike, a fact's stored-but-hidden range included, with their uncertainty.
    public func derivedSpan(of entity: EntityID) throws -> TimeRange {
        let linked = try db.writer.read { db in
            try Memory.fetchAll(db, sql: "select distinct memory.* from memory join moment_entity me on me.memory_id = memory.id where me.entity_id = ?",
                                arguments: [entity.rawValue])
        }
        var span = ChapterRepository.span(over: linked.map(\.range))
        // Its uncertainty is the weakest of its members': said only when every member was said.
        let placed = linked.map(\.range).filter(\.isPlaced)
        if span.isPlaced { span.origin = placed.allSatisfy { $0.origin == .stated || $0.origin == .confirmed } ? .stated : .inferred }
        return span
    }

    /// What the page shows: the span the person stated, else the derived one.
    public func span(of entity: EntityID) throws -> TimeRange {
        if let stated = try self.entity(id: entity)?.range, stated.isPlaced { return stated }
        return try derivedSpan(of: entity)
    }

    /// "Add dates", and only that: the person's own span, stored as said.
    public func setStatedSpan(_ entity: EntityID, _ range: TimeRange) throws {
        try db.writer.write { db in
            guard var row = try Entity.fetchOne(db, key: entity.rawValue) else { return }
            row.range = range
            try row.update(db)
        }
    }

    public func insertSpan(_ span: EntitySpan) throws {
        try db.writer.write { try span.insertIgnoringDuplicate($0) }
    }

    public func spans(of entity: EntityID) throws -> [EntitySpan] {
        try db.writer.read { try EntitySpan.filter(Column("entity_id") == entity.rawValue).order(Column("order")).fetchAll($0) }
    }
}

// MARK: - Records

extension Entity: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entity"

    public init(row: Row) throws {
        self.init(id: EntityID(rawValue: row["id"]), type: EntityType(rawValue: row["type"]) ?? .thing, title: row["title"],
                  detailText: row["detail_text"], createdFromCandidateID: (row["created_from_candidate_id"] as String?).map(CandidateID.init(rawValue:)),
                  createdAt: row["created_at"],
                  range: TimeRange(earliest: (row["earliest"] as String?).flatMap(CivilDate.init(iso:)),
                                   latest: (row["latest"] as String?).flatMap(CivilDate.init(iso:)),
                                   likelyStart: (row["likely_start"] as String?).flatMap(CivilDate.init(iso:)),
                                   likelyEnd: (row["likely_end"] as String?).flatMap(CivilDate.init(iso:)),
                                   granularity: (row["granularity"] as String?).flatMap(Granularity.init(rawValue:)),
                                   origin: (row["origin"] as String?).flatMap(RangeOrigin.init(rawValue:)),
                                   evidenceText: row["evidence_text"]),
                  hiddenFromTimeline: row["hidden_from_timeline"], excludedFromAI: row["excluded_from_ai"])
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.rawValue
        container["type"] = type.rawValue
        container["title"] = title
        container["detail_text"] = detailText
        container["created_from_candidate_id"] = createdFromCandidateID?.rawValue
        container["created_at"] = createdAt
        container["earliest"] = range.earliest?.iso
        container["latest"] = range.latest?.iso
        container["likely_start"] = range.likelyStart?.iso
        container["likely_end"] = range.likelyEnd?.iso
        container["granularity"] = range.granularity?.rawValue
        container["origin"] = range.origin?.rawValue
        container["evidence_text"] = range.evidenceText
        container["hidden_from_timeline"] = hiddenFromTimeline
        container["excluded_from_ai"] = excludedFromAI
    }
}

extension MomentEntity: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "moment_entity"

    public init(row: Row) throws {
        self.init(memoryID: MemoryID(rawValue: row["memory_id"]), entityID: EntityID(rawValue: row["entity_id"]),
                  relation: EntityRelation(rawValue: row["relation"]) ?? .mention, roleText: row["role_text"])
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["memory_id"] = memoryID.rawValue
        container["entity_id"] = entityID.rawValue
        container["relation"] = relation.rawValue
        container["role_text"] = roleText
    }

    func insertIgnoringDuplicate(_ db: Database) throws {
        try db.execute(sql: "insert or ignore into moment_entity (memory_id, entity_id, relation, role_text) values (?, ?, ?, ?)",
                       arguments: [memoryID.rawValue, entityID.rawValue, relation.rawValue, roleText])
    }
}

extension EntitySpan: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entity_span"

    public init(row: Row) throws {
        self.init(entityID: EntityID(rawValue: row["entity_id"]), segmentID: SegmentID(rawValue: row["segment_id"]),
                  startMs: row["start_ms"], endMs: row["end_ms"], order: row["order"])
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["entity_id"] = entityID.rawValue
        container["segment_id"] = segmentID.rawValue
        container["start_ms"] = startMs
        container["end_ms"] = endMs
        container["order"] = order
    }

    func insertIgnoringDuplicate(_ db: Database) throws {
        try db.execute(sql: "insert or ignore into entity_span (entity_id, segment_id, start_ms, end_ms, \"order\") values (?, ?, ?, ?, ?)",
                       arguments: [entityID.rawValue, segmentID.rawValue, startMs, endMs, order])
    }
}
