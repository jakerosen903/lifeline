import Foundation
import GRDB

/// People, places, things and ideas, and the one table that links them to memories (M7).
/// Titles match by `MatchKey`: case, outer space and sentence punctuation at the ends are ignored, never spelling.
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

    /// The entity of this type that the title names: the one made first among those with the
    /// same match key, so "Ohio." finds "Ohio". The rows of one type are read and compared here;
    /// the table is small, and SQL cannot compute the key. An empty key finds nothing.
    static func find(type: EntityType, title: String, in db: Database) throws -> Entity? {
        let key = MatchKey.of(title)
        guard !key.isEmpty else { return nil }
        return try Entity.fetchAll(db, sql: "select * from entity where type = ? order by created_at, rowid", arguments: [type.rawValue])
            .first { MatchKey.of($0.title) == key }
    }

    // MARK: - Two entities that are one

    /// Everything `source` holds moves to `target`, and `source` is deleted. One transaction: a
    /// kill part-way leaves both as they were. Returns false, and changes nothing, when the two
    /// are the same, either is gone, their types differ, or they are people (two people can
    /// share a name; only the person can say they are one).
    ///
    /// What moves: links to memories (a memory linked to both keeps one link of each relation),
    /// first tellings (after the target's own), tags, curiosity items and a session's subject.
    /// `target` keeps its title, its dates and its one-line detail, and takes `source`'s where it
    /// has none. When both have a detail line, or both have dates, and they differ, nothing is
    /// joined: a merge never drops what the person said. Hidden or excluded on either side stays
    /// hidden or excluded: a merge never reveals what the person put away.
    @discardableResult
    public func merge(_ source: EntityID, into target: EntityID) throws -> Bool {
        try db.writer.write { try Self.merge(source, into: target, in: $0) }
    }

    static func merge(_ source: EntityID, into target: EntityID, in db: Database) throws -> Bool {
        guard source != target, let leaving = try Entity.fetchOne(db, key: source.rawValue),
              var staying = try Entity.fetchOne(db, key: target.rawValue),
              leaving.type == staying.type, leaving.type != .person else { return false }
        // Each entity holds one detail line and one set of dates. When both sides have one and they
        // differ, joining would drop the person's words or dates, so the pair is left as it is.
        if let mine = staying.detailText, let theirs = leaving.detailText, mine != theirs { return false }
        if staying.range.isPlaced, leaving.range.isPlaced, staying.range != leaving.range { return false }
        // Photos (S4) links a photo to an entity. Its rules for covers live with that table, so a
        // pair that has photos on the side that would go is left for that code to join.
        if try db.tableExists("photo_link"),
           try Int.fetchOne(db, sql: "select count(*) from photo_link where entity_id = ?", arguments: [source.rawValue]) ?? 0 > 0 { return false }

        let s = source.rawValue, t = target.rawValue
        // A memory linked to both keeps the target's row; that row takes the stronger origin first (R6).
        for link in try MomentEntity.filter(Column("entity_id") == s).fetchAll(db) {
            try MomentEntity.raiseOrigin(link.memoryID, target, link.relation, to: link.origin, in: db)
        }
        try db.execute(sql: "update or ignore moment_entity set entity_id = ? where entity_id = ?", arguments: [t, s])
        let last = try Int.fetchOne(db, sql: "select max(\"order\") from entity_span where entity_id = ?", arguments: [t]) ?? -1
        let orders = try Int.fetchAll(db, sql: "select \"order\" from entity_span where entity_id = ? order by \"order\"", arguments: [s])
        for (offset, order) in orders.enumerated() {
            try db.execute(sql: "update entity_span set entity_id = ?, \"order\" = ? where entity_id = ? and \"order\" = ?",
                           arguments: [t, last + 1 + offset, s, order])
        }
        try db.execute(sql: "update or ignore domain_tag set element_id = ? where element_kind = ? and element_id = ?",
                       arguments: [t, ElementKind.entity.rawValue, s])
        try db.execute(sql: "delete from domain_tag where element_kind = ? and element_id = ?", arguments: [ElementKind.entity.rawValue, s])
        try db.execute(sql: "update curiosity_item set entity_id = ? where entity_id = ?", arguments: [t, s])
        try db.execute(sql: "update session set subject_entity_id = ? where subject_entity_id = ?", arguments: [t, s])

        if staying.detailText == nil { staying.detailText = leaving.detailText }
        if !staying.range.isPlaced { staying.range = leaving.range }
        staying.hiddenFromTimeline = staying.hiddenFromTimeline || leaving.hiddenFromTimeline
        staying.excludedFromAI = staying.excludedFromAI || leaving.excludedFromAI
        try staying.update(db)
        // Links the target already had stayed behind on the source; the delete takes them with it.
        _ = try Entity.deleteOne(db, key: s)
        return true
    }

    /// Places and things that share a type and a match key become one: each later copy joins the
    /// one made first ("Ohio." joins "Ohio"). People and ideas are never joined by name. One
    /// transaction. Returns what was joined, for the notice.
    @discardableResult
    public func mergeDuplicateTitles() throws -> [StoryRepository.MergedTitle] {
        try db.writer.write { db in
            var first: [String: Entity] = [:]
            var copies: [String: Int] = [:]
            var found: [String] = []
            let rows = try Entity.fetchAll(db, sql: "select * from entity where type in (?, ?) order by created_at, rowid",
                                           arguments: [EntityType.place.rawValue, EntityType.thing.rawValue])
            for entity in rows {
                let name = MatchKey.of(entity.title)
                guard !name.isEmpty else { continue }
                let key = entity.type.rawValue + "\u{1F}" + name
                guard let kept = first[key] else { first[key] = entity; continue }
                guard try Self.merge(entity.id, into: kept.id, in: db) else { continue }
                if copies[key] == nil { found.append(key) }
                copies[key, default: 1] += 1
            }
            return found.map { StoryRepository.MergedTitle(title: first[$0]?.title ?? "", copies: copies[$0] ?? 0) }
        }
    }

    /// A person goes through the People rename: the name is the owner's now (R39), and the old
    /// spelling stays an alias.
    public func rename(_ id: EntityID, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.emptyTitle }
        try db.writer.write { db in
            if try Person.exists(db, key: id.rawValue) {
                try PeopleRepository.rename(PersonID(rawValue: id.rawValue), to: trimmed, in: db)
            } else {
                try db.execute(sql: "update entity set title = ? where id = ?", arguments: [trimmed, id.rawValue])
            }
        }
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
            return entities.first { $0.type == type && MatchKey.of($0.title) == MatchKey.of(title) }
        }

        /// The union with another plan; an entity both planned keeps this plan's id.
        mutating func merge(_ other: Write) -> [EntityID: EntityID] {
            var remap: [EntityID: EntityID] = [:]
            for entity in other.entities {
                if let mine = planned(entity.type, entity.title) { remap[entity.id] = mine.id } else { entities.append(entity) }
            }
            // A person both plans made for one name is this plan's person; the other's row would have no entity.
            persons += other.persons.filter { p in !persons.contains { $0.id == p.id } && remap[p.entityID] == nil }
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
        for link in write.links { try link.insertKeepingStrongerOrigin(db) }
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

    /// One link per memory, entity and relation; a second keeps the first role text and the stronger origin.
    public func link(_ memory: MemoryID, _ entity: EntityID, relation: EntityRelation, roleText: String? = nil, origin: LinkOrigin? = nil) throws {
        try db.writer.write { try MomentEntity(memoryID: memory, entityID: entity, relation: relation, roleText: roleText, origin: origin).insertKeepingStrongerOrigin($0) }
    }

    /// A detail leaves every entity it was on and lands on `entity` (nil: none), in one write.
    /// The owner placed it, so a person's detail is `confirmed`; a thing, place or idea has no origin.
    public func moveDetail(_ memory: MemoryID, to entity: EntityID?) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from moment_entity where memory_id = ? and relation = 'detail'", arguments: [memory.rawValue])
            guard let entity else { return }
            let origin: LinkOrigin? = try Person.exists(db, key: entity.rawValue) ? .confirmed : nil
            try MomentEntity(memoryID: memory, entityID: entity, relation: .detail, origin: origin).insertIgnoringDuplicate(db)
        }
    }

    /// True when the memory is already a detail of something.
    public func hasDetail(_ memory: MemoryID) throws -> Bool {
        try db.writer.read { db in
            try Int.fetchOne(db, sql: "select count(*) from moment_entity where memory_id = ? and relation = 'detail'", arguments: [memory.rawValue]) ?? 0 > 0
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

    // MARK: - Batched reads

    /// A told moment: an event or other, not hidden, with a candidate (a floating stand-in is not told).
    private static let toldAndVisible = "memory.hidden_from_timeline = 0 and memory.created_from_candidate_id is not null"
    private static let toldMoment = "memory.kind in ('event', 'other') and \(toldAndVisible)"
    private static let ownerEntity = "select entity_id from person where is_owner = 1"

    /// Every linked memory of every entity of a type, in one query. An entity with no linked
    /// memory is absent. Each memory is listed once per entity, oldest told first. It does not
    /// filter hidden entities: callers pair it with `entities(type:)`, which does.
    public func strips(type: EntityType) throws -> [EntityID: [LinkedTime]] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select me.entity_id, memory.id, memory.earliest, memory.latest, memory.likely_start, memory.likely_end,
                       memory.granularity, memory.origin, memory.evidence_text,
                       max(me.relation = 'mention' and \(Self.toldMoment)) as is_moment
                from moment_entity me
                join entity on entity.id = me.entity_id
                join memory on memory.id = me.memory_id
                where entity.type = ?
                group by me.entity_id, memory.id
                order by memory.created_at, memory.id
                """, arguments: [type.rawValue])
            var strips: [EntityID: [LinkedTime]] = [:]
            for row in rows {
                let time = LinkedTime(memoryID: MemoryID(rawValue: row["id"]), range: TimeRange(memoryRow: row), isMoment: row["is_moment"])
                strips[EntityID(rawValue: row["entity_id"]), default: []].append(time)
            }
            return strips
        }
    }

    /// The entities that share told moments with `entity`, most shared first, then by title.
    /// A shared moment is a memory of kind event or other, not hidden and told, that links both
    /// entities by any relation (plan decision 3).
    /// The owner, ideas and hidden entities never appear; nothing is linked that was not told.
    public func coOccurrences(of entity: EntityID, minimumShared: Int = 2) throws -> [CoOccurrence] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select other.*, count(distinct memory.id) as shared
                from moment_entity mine
                join moment_entity theirs on theirs.memory_id = mine.memory_id and theirs.entity_id <> mine.entity_id
                join memory on memory.id = mine.memory_id
                join entity other on other.id = theirs.entity_id
                where mine.entity_id = ? and \(Self.toldMoment)
                  and other.hidden_from_timeline = 0 and other.type <> 'idea' and other.id not in (\(Self.ownerEntity))
                group by other.id
                having shared >= ?
                order by shared desc, other.title collate nocase, other.id
                """, arguments: [entity.rawValue, minimumShared])
            return try rows.map { CoOccurrence(entity: try Entity(row: $0), sharedMoments: $0["shared"]) }
        }
    }

    /// The words the person used for each entity of a type, where they used any. A role text
    /// counts only from a told memory that is not hidden.
    public func ownWords(type: EntityType) throws -> [EntityID: String] {
        try db.writer.read { try Self.ownWords(where: "entity.type = ?", arguments: [type.rawValue], in: $0) }
    }

    public func ownWords(of entity: EntityID) throws -> String? {
        try db.writer.read { try Self.ownWords(where: "entity.id = ?", arguments: [entity.rawValue], in: $0)[entity] }
    }

    private static func ownWords(where condition: String, arguments: StatementArguments, in db: Database) throws -> [EntityID: String] {
        var titles: [EntityID: String] = [:]
        var aliases: [EntityID: [String]] = [:]
        for row in try Row.fetchAll(db, sql: """
            select entity.id, entity.title, alias.text from alias
            join person on person.id = alias.person_id
            join entity on entity.id = person.entity_id
            where \(condition) order by alias.text
            """, arguments: arguments) {
            let id = EntityID(rawValue: row["id"])
            titles[id] = row["title"]
            aliases[id, default: []].append(row["text"])
        }
        var roleTexts: [EntityID: [String]] = [:]
        for row in try Row.fetchAll(db, sql: """
            select entity.id, entity.title, me.role_text from moment_entity me
            join entity on entity.id = me.entity_id
            join memory on memory.id = me.memory_id
            where \(condition) and me.role_text is not null and \(Self.toldAndVisible)
            """, arguments: arguments) {
            let id = EntityID(rawValue: row["id"])
            titles[id] = row["title"]
            roleTexts[id, default: []].append(row["role_text"])
        }
        return titles.reduce(into: [:]) { words, entry in
            let (id, title) = entry
            words[id] = OwnWords.choose(title: title, aliases: aliases[id, default: []], roleTexts: roleTexts[id, default: []])
        }
    }

    /// Every visible entity of a type with its strip, span and own words, by title, in four queries
    /// however many entities there are.
    public func summaries(type: EntityType) throws -> [EntitySummary] {
        let entities = try entities(type: type)
        let strips = try strips(type: type)
        let words = try ownWords(type: type)
        return entities.map { entity in
            let linked = strips[entity.id, default: []]
            let stated = entity.range.isPlaced ? entity.range : nil
            return EntitySummary(entity: entity, ownWords: words[entity.id],
                                 momentRanges: linked.filter(\.isMoment).map(\.range),
                                 span: stated ?? Self.derivedSpan(over: linked.map(\.range)))
        }
    }

    /// The first telling (lowest `order`) of every entity of a type that has a span, with its
    /// session, in one query.
    public func firstTellings(type: EntityType) throws -> [EntityID: Telling] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select span.entity_id, span.start_ms, span.end_ms, session.id as session_id, session.audio_path, session.started_at
                from (select entity_id, min("order") as first_order from entity_span group by entity_id) first
                join entity_span span on span.entity_id = first.entity_id and span."order" = first.first_order
                join entity on entity.id = span.entity_id
                join segment on segment.id = span.segment_id
                join session on session.id = segment.session_id
                where entity.type = ?
                """, arguments: [type.rawValue])
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                (EntityID(rawValue: row["entity_id"]),
                 Telling(sessionID: SessionID(rawValue: row["session_id"]), audioPath: row["audio_path"],
                         range: MsRange(start: row["start_ms"], end: row["end_ms"]), toldAt: row["started_at"]))
            })
        }
    }

    /// What each told, visible memory of these kinds is linked to, in one query. Hidden entities
    /// are kept: the caller decides what a hidden link means. Each list reads `detail` before
    /// `mention`, then by title ignoring case.
    public func aboutLinks(kinds: Set<MemoryKind>) throws -> [MemoryID: [AboutLink]] {
        guard !kinds.isEmpty else { return [:] }
        return try db.writer.read { db in
            let marks = databaseQuestionMarks(count: kinds.count)
            let rows = try Row.fetchAll(db, sql: """
                select entity.*, me.memory_id as link_memory_id, me.relation as link_relation
                from moment_entity me
                join entity on entity.id = me.entity_id
                join memory on memory.id = me.memory_id
                where memory.kind in (\(marks)) and \(Self.toldAndVisible)
                order by me.memory_id, me.relation = 'mention', entity.title collate nocase, entity.id
                """, arguments: StatementArguments(kinds.map(\.rawValue)))
            var links: [MemoryID: [AboutLink]] = [:]
            for row in rows {
                let relation = EntityRelation(rawValue: row["link_relation"]) ?? .mention
                links[MemoryID(rawValue: row["link_memory_id"]), default: []].append(AboutLink(entity: try Entity(row: row), relation: relation))
            }
            return links
        }
    }

    // MARK: - Spans

    /// Derived, never asked: the earliest and latest of everything linked, moments and details
    /// alike, a fact's stored-but-hidden range included, with their uncertainty.
    public func derivedSpan(of entity: EntityID) throws -> TimeRange {
        let linked = try db.writer.read { db in
            try Memory.fetchAll(db, sql: "select distinct memory.* from memory join moment_entity me on me.memory_id = memory.id where me.entity_id = ?",
                                arguments: [entity.rawValue])
        }
        return Self.derivedSpan(over: linked.map(\.range))
    }

    /// The rule behind `derivedSpan(of:)`, over ranges already read.
    static func derivedSpan(over ranges: [TimeRange]) -> TimeRange {
        var span = ChapterRepository.span(over: ranges)
        // Its uncertainty is the weakest of its members': said only when every member was said.
        let placed = ranges.filter(\.isPlaced)
        if span.isPlaced { span.origin = placed.allSatisfy(\.readsAsSaid) ? .stated : .inferred }
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

private extension TimeRange {
    /// A memory's range from a row with the memory's range columns, unprefixed.
    init(memoryRow row: Row) {
        self.init(earliest: (row["earliest"] as String?).flatMap(CivilDate.init(iso:)),
                  latest: (row["latest"] as String?).flatMap(CivilDate.init(iso:)),
                  likelyStart: (row["likely_start"] as String?).flatMap(CivilDate.init(iso:)),
                  likelyEnd: (row["likely_end"] as String?).flatMap(CivilDate.init(iso:)),
                  granularity: (row["granularity"] as String?).flatMap(Granularity.init(rawValue:)),
                  origin: (row["origin"] as String?).flatMap(RangeOrigin.init(rawValue:)),
                  evidenceText: row["evidence_text"])
    }
}

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
                  relation: EntityRelation(rawValue: row["relation"]) ?? .mention, roleText: row["role_text"],
                  origin: (row["origin"] as String?).flatMap(LinkOrigin.init(rawValue:)), personHandle: row["person_handle"])
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["memory_id"] = memoryID.rawValue
        container["entity_id"] = entityID.rawValue
        container["relation"] = relation.rawValue
        container["role_text"] = roleText
        container["origin"] = origin?.rawValue
        container["person_handle"] = personHandle
    }

    func insertIgnoringDuplicate(_ db: Database) throws {
        try db.execute(sql: "insert or ignore into moment_entity (memory_id, entity_id, relation, role_text, origin, person_handle) values (?, ?, ?, ?, ?, ?)",
                       arguments: [memoryID.rawValue, entityID.rawValue, relation.rawValue, roleText, origin?.rawValue, personHandle])
    }

    /// Inserts the link, or, when the memory already has it, keeps that row (its role text and
    /// handle) and raises its origin when this one is stronger. A link is never weakened.
    func insertKeepingStrongerOrigin(_ db: Database) throws {
        try insertIgnoringDuplicate(db)
        try Self.raiseOrigin(memoryID, entityID, relation, to: origin, in: db)
    }

    /// Sets the row's origin to the stronger of its own and `origin`. No row, no change.
    static func raiseOrigin(_ memory: MemoryID, _ entity: EntityID, _ relation: EntityRelation, to origin: LinkOrigin?, in db: Database) throws {
        guard let origin else { return }
        let key: [any DatabaseValueConvertible] = [memory.rawValue, entity.rawValue, relation.rawValue]
        guard let row = try Row.fetchOne(db, sql: "select origin from moment_entity where memory_id = ? and entity_id = ? and relation = ?",
                                         arguments: StatementArguments(key)) else { return }
        let current = (row["origin"] as String?).flatMap(LinkOrigin.init(rawValue:))
        guard let stronger = LinkOrigin.stronger(current, origin), stronger != current else { return }
        try db.execute(sql: "update moment_entity set origin = ? where memory_id = ? and entity_id = ? and relation = ?",
                       arguments: StatementArguments([stronger.rawValue] + key))
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
