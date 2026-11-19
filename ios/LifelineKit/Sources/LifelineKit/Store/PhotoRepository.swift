import Foundation
import GRDB

/// Photos and the links that put them on a page (S4). A photo is one row and one file; a link says which
/// subject shows it. Each subject has at most one cover. The repository never touches the files.
public struct PhotoRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    // MARK: - Reads

    public func photo(id: PhotoID) throws -> Photo? {
        try db.writer.read { try Photo.fetchOne($0, key: id.rawValue) }
    }

    public func photo(sha256: String) throws -> Photo? {
        try db.writer.read { try Photo.filter(Column("sha256") == sha256).fetchOne($0) }
    }

    /// Cover first, then by `sort_order` (the order added).
    public func photos(of subject: PhotoSubject) throws -> [PlacedPhoto] {
        try db.writer.read { db in
            let (column, value) = subject.key
            let rows = try Row.fetchAll(db, sql: """
                select photo.*, photo_link.role as link_role from photo_link
                join photo on photo.id = photo_link.photo_id
                where photo_link.\(column) = ?
                order by photo_link.role = 'cover' desc, photo_link.sort_order, photo_link.rowid
                """, arguments: [value])
            return try rows.map { PlacedPhoto(photo: try Photo(row: $0), role: PhotoRole(rawValue: $0["link_role"]) ?? .attached) }
        }
    }

    /// One statement: the cover of every entity of a type that is not hidden.
    public func covers(type: EntityType) throws -> [EntityID: Photo] {
        try db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                select photo.*, photo_link.entity_id as link_entity_id from photo_link
                join photo on photo.id = photo_link.photo_id
                join entity on entity.id = photo_link.entity_id
                where photo_link.role = 'cover' and entity.type = ? and entity.hidden_from_timeline = 0
                """, arguments: [type.rawValue])
            var covers: [EntityID: Photo] = [:]
            for row in rows { covers[EntityID(rawValue: row["link_entity_id"])] = try Photo(row: row) }
            return covers
        }
    }

    /// The entities whose link to this photo a story made.
    public func storyPages(of photo: PhotoID) throws -> Set<EntityID> {
        try db.writer.read { db in
            Set(try String.fetchAll(db, sql: "select entity_id from photo_link where photo_id = ? and entity_id is not null and origin = ?",
                                    arguments: [photo.rawValue, PhotoLinkOrigin.story.rawValue]).map(EntityID.init(rawValue:)))
        }
    }

    /// True when the owner took this photo off this page. A story does not put it back.
    public func isDeclined(_ photo: PhotoID, on entity: EntityID) throws -> Bool {
        try db.writer.read { try Self.isDeclined(photo, on: entity, in: $0) }
    }

    private static func isDeclined(_ photo: PhotoID, on entity: EntityID, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "select exists (select 1 from photo_page_declined where photo_id = ? and entity_id = ?)",
                          arguments: [photo.rawValue, entity.rawValue]) ?? false
    }

    public func fileNames() throws -> Set<String> {
        try db.writer.read { Set(try String.fetchAll($0, sql: "select file_name from photo")) }
    }

    // MARK: - Writes

    /// The photo a session is about, if it still points at one.
    public func subjectPhoto(of session: SessionID) throws -> Photo? {
        try db.writer.read { try Self.subjectPhoto(of: session, in: $0) }
    }

    /// True when the photo has a home besides this session: a link to an entity, a link to a memory with a span
    /// outside this session, or another session that points at it.
    public func hasOtherHome(_ photo: PhotoID, than session: SessionID) throws -> Bool {
        try db.writer.read { db in
            try Bool.fetchOne(db, sql: """
                select exists (select 1 from photo_link where photo_id = ?1 and entity_id is not null)
                    or exists (
                        select 1 from photo_link
                        join memory_span on memory_span.memory_id = photo_link.memory_id
                        join segment on segment.id = memory_span.segment_id
                        where photo_link.photo_id = ?1 and segment.session_id <> ?2)
                    or exists (select 1 from session where subject_photo_id = ?1 and id <> ?2)
                """, arguments: [photo.rawValue, session.rawValue]) ?? false
        }
    }

    /// Inserts a photo row with no link. A session row that points at it, or a later link, gives it a home;
    /// until then the launch sweep removes it.
    public func insert(_ photo: Photo) throws {
        try db.writer.write { try photo.insert($0) }
    }

    /// One transaction: the row, then its link. The first photo on a subject is its cover (decision 8).
    public func insert(_ photo: Photo, linkingTo subject: PhotoSubject) throws {
        try db.writer.write { db in
            try photo.insert(db)
            try Self.link(photo.id, to: subject, in: db)
        }
    }

    /// The owner links an existing photo. The first photo on a subject is its cover. On an entity's page this is the
    /// owner's choice, in one write: the decline for the pair goes, and a link a story made becomes the owner's.
    /// Already linked by the owner: nothing changes.
    public func link(_ photo: PhotoID, to subject: PhotoSubject) throws {
        try db.writer.write { db in
            try Self.link(photo, to: subject, in: db)
            guard case .entity(let entity) = subject else { return }
            try db.execute(sql: "delete from photo_page_declined where photo_id = ? and entity_id = ?", arguments: [photo.rawValue, entity.rawValue])
            try db.execute(sql: "update photo_link set origin = null where photo_id = ? and entity_id = ?", arguments: [photo.rawValue, entity.rawValue])
        }
    }

    /// One write. The page's photos get `sort_order` 0, 1, 2…: first the ids of `photos` that the page holds, each one time, in the
    /// order given; then the page's other photos in the order a read shows them today. The first is the cover.
    public func reorder(_ photos: [PhotoID], of subject: PhotoSubject) throws {
        try db.writer.write { try Self.writeOrder(photos, of: subject, in: $0) }
    }

    /// Moves the photo to the front: `reorder([photo], of: subject)`. A photo the page does not hold changes nothing.
    public func setCover(_ photo: PhotoID, of subject: PhotoSubject) throws {
        try db.writer.write { db in
            let (column, value) = subject.key
            let linked = try Int.fetchOne(db, sql: "select count(*) from photo_link where \(column) = ? and photo_id = ?",
                                          arguments: [value, photo.rawValue]) ?? 0
            guard linked == 1 else { return }
            try Self.writeOrder([photo], of: subject, in: db)
        }
    }

    /// The five steps, in this order, because the unique cover index allows one cover per page and is checked per statement:
    /// read the rows as a read shows them; stop on none; demote every cover; number the rows from 0; promote the first.
    private static func writeOrder(_ wanted: [PhotoID], of subject: PhotoSubject, in db: Database) throws {
        let (column, value) = subject.key
        let held = try String.fetchAll(db, sql: """
            select photo_id from photo_link where \(column) = ? order by role = 'cover' desc, sort_order, rowid
            """, arguments: [value]).map(PhotoID.init(rawValue:))
        guard !held.isEmpty else { return }
        var ordered: [PhotoID] = [], seen = Set<PhotoID>()
        for id in wanted where held.contains(id) && seen.insert(id).inserted { ordered.append(id) }
        ordered += held.filter { !seen.contains($0) }
        try db.execute(sql: "update photo_link set role = 'attached' where \(column) = ? and role = 'cover'", arguments: [value])
        for (index, id) in ordered.enumerated() {
            try db.execute(sql: "update photo_link set sort_order = ? where \(column) = ? and photo_id = ?",
                           arguments: [index, value, id.rawValue])
        }
        try db.execute(sql: "update photo_link set role = 'cover' where \(column) = ? and photo_id = ?", arguments: [value, ordered[0].rawValue])
    }

    /// One transaction. Removes the link; a removed cover passes to the oldest-added photo left. Returns
    /// the photo when no link is left and its row was deleted, so the caller deletes the file.
    /// Off an entity's page, the owner's removal is recorded, so a story does not put the photo back. A photo the page
    /// does not hold records nothing. When the photo row goes, its declines go with it (cascade).
    public func unlink(_ photo: PhotoID, from subject: PhotoSubject) throws -> Photo? {
        try db.writer.write { db in
            guard try Self.removeLink(photo, from: subject, in: db) else { return nil }
            if case .entity(let entity) = subject {
                try db.execute(sql: "insert or ignore into photo_page_declined (photo_id, entity_id) values (?, ?)",
                               arguments: [photo.rawValue, entity.rawValue])
            }
            return try Self.deleteIfHomeless(photo, in: db)
        }
    }

    /// Removes one link and passes a removed cover to the oldest-added photo left. False when there was no link.
    static func removeLink(_ photo: PhotoID, from subject: PhotoSubject, in db: Database) throws -> Bool {
        let (column, value) = subject.key
        guard let role = try String.fetchOne(db, sql: "select role from photo_link where \(column) = ? and photo_id = ?",
                                             arguments: [value, photo.rawValue]) else { return false }
        try db.execute(sql: "delete from photo_link where \(column) = ? and photo_id = ?", arguments: [value, photo.rawValue])
        if role == PhotoRole.cover.rawValue {
            try db.execute(sql: """
                update photo_link set role = 'cover' where rowid = (
                    select rowid from photo_link where \(column) = ? order by sort_order, rowid limit 1)
                """, arguments: [value])
        }
        return true
    }

    /// Every memory and entity that holds the photo, in one read.
    public func subjects(of photo: PhotoID) throws -> (memories: Set<MemoryID>, entities: Set<EntityID>) {
        try db.writer.read { db in
            var memories = Set<MemoryID>(), entities = Set<EntityID>()
            for row in try Row.fetchAll(db, sql: "select memory_id, entity_id from photo_link where photo_id = ?", arguments: [photo.rawValue]) {
                if let id = row["memory_id"] as String? { memories.insert(MemoryID(rawValue: id)) }
                if let id = row["entity_id"] as String? { entities.insert(EntityID(rawValue: id)) }
            }
            return (memories, entities)
        }
    }

    public func isLinked(_ photo: PhotoID, to subject: PhotoSubject) throws -> Bool {
        try db.writer.read { db in
            let (column, value) = subject.key
            return try Bool.fetchOne(db, sql: "select exists (select 1 from photo_link where \(column) = ? and photo_id = ?)",
                                     arguments: [value, photo.rawValue]) ?? false
        }
    }

    /// One transaction. The session stops pointing at its photo. When no other session points at it, the page links
    /// a story made go too (plan decision 9); the owner's links stay. When the photo then has no link and no other
    /// session, its row is deleted and returned so the caller deletes the file.
    public func letGo(of session: SessionID) throws -> Photo? {
        try db.writer.write { db in
            guard let photo = try Self.subjectPhoto(of: session, in: db) else { return nil }
            try db.execute(sql: "update session set subject_photo_id = null where id = ?", arguments: [session.rawValue])
            let pointedAt = try Bool.fetchOne(db, sql: "select exists (select 1 from session where subject_photo_id = ?)",
                                              arguments: [photo.id.rawValue]) ?? false
            if !pointedAt { try Self.removeStoryLinks(of: photo.id, in: db) }
            return try Self.deleteIfHomeless(photo.id, in: db)
        }
    }

    /// Removes each page link a story made for the photo. No decline is recorded: the owner did not take it off one page.
    private static func removeStoryLinks(of photo: PhotoID, in db: Database) throws {
        let pages = try String.fetchAll(db, sql: "select entity_id from photo_link where photo_id = ? and entity_id is not null and origin = ?",
                                        arguments: [photo.rawValue, PhotoLinkOrigin.story.rawValue])
        for page in pages { _ = try removeLink(photo, from: .entity(EntityID(rawValue: page)), in: db) }
    }

    /// Deletes every photo row with no link and no session that points at it; returns them.
    public func deleteUnlinked() throws -> [Photo] {
        try db.writer.write { db in
            let orphans = try Photo.fetchAll(db, sql: "select * from photo where \(Self.homeless)")
            try db.execute(sql: "delete from photo where \(Self.homeless)")
            return orphans
        }
    }

    /// A photo is homeless when no link and no session holds it.
    private static let homeless = """
        id not in (select photo_id from photo_link) and id not in (select subject_photo_id from session where subject_photo_id is not null)
        """

    private static func subjectPhoto(of session: SessionID, in db: Database) throws -> Photo? {
        try Photo.fetchOne(db, sql: """
            select photo.* from session join photo on photo.id = session.subject_photo_id where session.id = ?
            """, arguments: [session.rawValue])
    }

    private static func deleteIfHomeless(_ photo: PhotoID, in db: Database) throws -> Photo? {
        guard let row = try Photo.fetchOne(db, sql: "select * from photo where id = ? and \(homeless)", arguments: [photo.rawValue]) else { return nil }
        _ = try Photo.deleteOne(db, key: photo.rawValue)
        return row
    }

    /// A memory kept from, or merged with a telling of, a photo's story holds that photo (spec: a story about a photo).
    /// The segment's session names the photo; none named, nothing happens. Linking twice changes nothing.
    /// Returns the photo when this call wrote the link, nil when the memory already held it or there is no photo,
    /// so an undo takes back only what this write added.
    @discardableResult
    static func linkSubjectPhoto(ofSegment segment: SegmentID, to memory: MemoryID, in db: Database) throws -> PhotoID? {
        guard let photo = try subjectPhotoID(ofSegment: segment, in: db) else { return nil }
        return try link(photo, to: .memory(memory), in: db) ? photo : nil
    }

    private static func subjectPhotoID(ofSegment segment: SegmentID, in db: Database) throws -> PhotoID? {
        try String.fetchOne(db, sql: """
            select session.subject_photo_id from segment join session on session.id = segment.session_id where segment.id = ?
            """, arguments: [segment.rawValue]).map(PhotoID.init(rawValue:))
    }

    /// Inside the Keep write, after the memory's links are stored. Puts the photo on the page of each person the memory
    /// names, with origin `story`. Skips the owner, a hidden entity, a page that holds the photo, and a declined pair.
    /// Returns the entities it linked, in the order the memory's links were written.
    /// Every relation counts: a fact about Dad names Dad as a moment that mentions him does.
    @discardableResult
    static func linkToPeoplePages(_ photo: PhotoID, namedBy memory: MemoryID, in db: Database) throws -> [EntityID] {
        let people = try String.fetchAll(db, sql: """
            select moment_entity.entity_id from moment_entity
            join entity on entity.id = moment_entity.entity_id
            where moment_entity.memory_id = ? and entity.type = ? and entity.hidden_from_timeline = 0
              and entity.id not in (select entity_id from person where is_owner = 1 and entity_id is not null)
            group by moment_entity.entity_id
            order by min(moment_entity.rowid)
            """, arguments: [memory.rawValue, EntityType.person.rawValue]).map(EntityID.init(rawValue:))
        var linked: [EntityID] = []
        for person in people where try link(photo, to: .entity(person), origin: .story, in: db) { linked.append(person) }
        return linked
    }

    /// True when this call wrote the link; false when the subject already held the photo, whatever its origin.
    /// A `story` link to an entity the owner took the photo off is refused here, so no caller can forget the decline.
    /// An owner's link (no origin) is never refused.
    @discardableResult
    static func link(_ photo: PhotoID, to subject: PhotoSubject, origin: PhotoLinkOrigin? = nil, in db: Database) throws -> Bool {
        if origin == .story, case .entity(let entity) = subject, try isDeclined(photo, on: entity, in: db) { return false }
        let (column, value) = subject.key
        let linked = try Int.fetchOne(db, sql: "select count(*) from photo_link where \(column) = ? and photo_id = ?",
                                      arguments: [value, photo.rawValue]) ?? 0
        guard linked == 0 else { return false }
        let held = try Row.fetchOne(db, sql: """
            select max(sort_order) as top, max(role = 'cover') as has_cover from photo_link where \(column) = ?
            """, arguments: [value])
        let hasCover = (held?["has_cover"] as Int?) == 1
        let next = ((held?["top"] as Int?) ?? -1) + 1
        try db.execute(sql: "insert into photo_link (photo_id, \(column), role, sort_order, origin) values (?, ?, ?, ?, ?)",
                       arguments: [photo.rawValue, value, (hasCover ? PhotoRole.attached : .cover).rawValue, next, origin?.rawValue])
        return true
    }
}

private extension PhotoSubject {
    /// The link column that names this subject, and its value. Both come from this type, never from input.
    var key: (column: String, value: String) {
        switch self {
        case .entity(let id): ("entity_id", id.rawValue)
        case .memory(let id): ("memory_id", id.rawValue)
        }
    }
}

// MARK: - Records

extension Photo: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "photo"

    public init(row: Row) throws {
        self.init(id: PhotoID(rawValue: row["id"]), fileName: row["file_name"], assetLocalID: row["asset_local_id"],
                  takenAt: (row["taken_at"] as String?).flatMap(PhotoTakenAt.init(stored:)),
                  takenOrigin: (row["taken_origin"] as String?).flatMap(PhotoOrigin.init(rawValue:)),
                  lat: row["lat"], lon: row["lon"],
                  locationOrigin: (row["location_origin"] as String?).flatMap(PhotoOrigin.init(rawValue:)),
                  sha256: row["sha256"], pixelWidth: row["pixel_width"], pixelHeight: row["pixel_height"], addedAt: row["added_at"])
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.rawValue
        container["file_name"] = fileName
        container["asset_local_id"] = assetLocalID
        container["taken_at"] = takenAt?.stored
        container["taken_origin"] = takenOrigin?.rawValue
        container["lat"] = lat
        container["lon"] = lon
        container["location_origin"] = locationOrigin?.rawValue
        container["sha256"] = sha256
        container["pixel_width"] = pixelWidth
        container["pixel_height"] = pixelHeight
        container["added_at"] = addedAt
    }
}
