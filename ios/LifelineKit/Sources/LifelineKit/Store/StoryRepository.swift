import Foundation
import GRDB

/// Stories and their moments. Membership is one story per memory; moving a memory between
/// stories is `remove` then `add`. Deleting a story never touches a memory.
public struct StoryRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// A story with a given id, so a ref the queue minted can become the row later.
    @discardableResult
    public func insert(id: StoryID? = nil, title: String?, chapterID: ChapterID?) throws -> Story {
        let story = Story(id: id ?? StoryID(), title: Self.clean(title), chapterID: chapterID, createdAt: .now)
        try db.writer.write { try story.insert($0) }
        return story
    }

    public func story(id: StoryID) throws -> Story? {
        try db.writer.read { try Story.fetchOne($0, key: id.rawValue) }
    }

    public func stories() throws -> [Story] {
        try db.writer.read { try Story.order(Column("created_at")).fetchAll($0) }
    }

    public func story(of memory: MemoryID) throws -> Story? {
        try db.writer.read { db in
            try Story.fetchOne(db, sql: "select story.* from story join story_moment sm on sm.story_id = story.id where sm.memory_id = ?",
                               arguments: [memory.rawValue])
        }
    }

    /// Members in story order.
    public func members(of story: StoryID) throws -> [Memory] {
        try db.writer.read { db in
            try Memory.fetchAll(db, sql: """
                select memory.* from memory join story_moment sm on sm.memory_id = memory.id
                where sm.story_id = ? order by sm."order", memory.created_at
                """, arguments: [story.rawValue])
        }
    }

    /// Appends the memory. Throws when the memory is already in a story (one story per memory).
    public func add(memory: MemoryID, to story: StoryID) throws {
        try db.writer.write { db in
            let order = (try Int.fetchOne(db, sql: "select max(\"order\") from story_moment where story_id = ?", arguments: [story.rawValue]) ?? -1) + 1
            try StoryMoment(storyID: story, memoryID: memory, order: order).insert(db)
        }
    }

    public func remove(memory: MemoryID) throws {
        try db.writer.write { try $0.execute(sql: "delete from story_moment where memory_id = ?", arguments: [memory.rawValue]) }
    }

    public func rename(_ id: StoryID, title: String?) throws {
        try db.writer.write { try $0.execute(sql: "update story set title = ? where id = ?", arguments: [Self.clean(title), id.rawValue]) }
    }

    public func setChapter(_ id: StoryID, chapterID: ChapterID?) throws {
        try db.writer.write { try $0.execute(sql: "update story set chapter_id = ? where id = ?", arguments: [chapterID?.rawValue, id.rawValue]) }
    }

    public func delete(_ id: StoryID) throws {
        try db.writer.write { _ = try Story.deleteOne($0, key: id.rawValue) }
    }

    /// Stories with no member left, after a memory or session was deleted.
    @discardableResult
    public func deleteEmpty() throws -> Int {
        try db.writer.write { db in
            try db.execute(sql: "delete from story where not exists (select 1 from story_moment where story_moment.story_id = story.id)")
            return db.changesCount
        }
    }

    public func derivedSpan(of story: StoryID) throws -> TimeRange {
        ChapterRepository.span(over: try members(of: story).map(\.range))
    }

    private static func clean(_ title: String?) -> String? {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }
}
