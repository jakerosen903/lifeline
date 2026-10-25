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

    /// A memory's place in its story, with enough of the story to put it back if the story goes.
    public struct Membership: Sendable, Equatable {
        public var moment: StoryMoment
        public var title: String?
        public var chapterID: ChapterID?
    }

    public func membership(of memory: MemoryID) throws -> Membership? {
        try db.writer.read { db in
            guard let moment = try StoryMoment.filter(Column("memory_id") == memory.rawValue).fetchOne(db),
                  let story = try Story.fetchOne(db, key: moment.storyID.rawValue) else { return nil }
            return Membership(moment: moment, title: story.title, chapterID: story.chapterID)
        }
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
            try db.execute(sql: MemoryRepository.deleteEmptyStoriesSQL)
            return db.changesCount
        }
    }

    /// Puts memories into a story (made when `story` is nil, with `newStoryID` when given), each
    /// leaving any story it was in, emptied stories deleted, and a pair's status set, all in one
    /// transaction (M5 review).
    @discardableResult
    public func join(_ memories: [MemoryID], story: StoryID?, title: String?, chapterID: ChapterID?, newStoryID: StoryID? = nil,
                     markingPair pair: (id: DuplicatePairID, status: PairStatus)? = nil) throws -> Story {
        try db.writer.write { db in
            let target = try Self.join(memories, story: story, title: title, chapterID: chapterID, newStoryID: newStoryID, in: db)
            if let pair { try Self.setPair(pair.id, pair.status, in: db) }
            return target
        }
    }

    /// The membership half of `join`, inside a caller's transaction: Keep writes the memory and
    /// its story line as one.
    static func join(_ memories: [MemoryID], story: StoryID?, title: String?, chapterID: ChapterID?, newStoryID: StoryID?, in db: Database) throws -> Story {
            let target: Story
            if let story, let existing = try Story.fetchOne(db, key: story.rawValue) {
                target = existing
            } else {
                target = Story(id: story ?? newStoryID ?? StoryID(), title: Self.clean(title), chapterID: chapterID, createdAt: .now)
                try target.insert(db)
            }
            // Stories are for scenes: a fact, feeling or goal never joins one (M7).
            for memory in memories where try String.fetchOne(db, sql: "select kind from memory where id = ?", arguments: [memory.rawValue])
                .map({ MemoryKind(rawValue: $0)?.isMoment ?? true }) ?? true {
                try db.execute(sql: "delete from story_moment where memory_id = ?", arguments: [memory.rawValue])
                let order = (try Int.fetchOne(db, sql: "select max(\"order\") from story_moment where story_id = ?", arguments: [target.id.rawValue]) ?? -1) + 1
                try StoryMoment(storyID: target.id, memoryID: memory, order: order).insert(db)
            }
            try db.execute(sql: MemoryRepository.deleteEmptyStoriesSQL)
            return target
    }

    /// Takes memories out of their stories, deletes `deletingStory` and any emptied story, puts
    /// back the memberships in `restoring` (re-creating a story that went when the memory left
    /// it), and sets a pair's status, in one transaction.
    public func leave(_ memories: [MemoryID], deletingStory: StoryID?, restoring: [Membership] = [],
                      markingPair pair: (id: DuplicatePairID, status: PairStatus)? = nil) throws {
        try db.writer.write { db in
            for memory in memories { try db.execute(sql: "delete from story_moment where memory_id = ?", arguments: [memory.rawValue]) }
            if let deletingStory { _ = try Story.deleteOne(db, key: deletingStory.rawValue) }
            for membership in restoring {
                if try !Story.exists(db, key: membership.moment.storyID.rawValue) {
                    try Story(id: membership.moment.storyID, title: membership.title, chapterID: membership.chapterID, createdAt: .now).insert(db)
                }
                try db.execute(sql: "delete from story_moment where memory_id = ?", arguments: [membership.moment.memoryID.rawValue])
                try membership.moment.insert(db)
            }
            try db.execute(sql: MemoryRepository.deleteEmptyStoriesSQL)
            if let pair { try Self.setPair(pair.id, pair.status, in: db) }
        }
    }

    /// The taken members become a new, untitled story in the same chapter, in one transaction.
    @discardableResult
    public func split(_ story: StoryID, taking memories: [MemoryID]) throws -> Story {
        try db.writer.write { db in
            let chapter = try Story.fetchOne(db, key: story.rawValue)?.chapterID
            let fresh = Story(id: StoryID(), title: nil, chapterID: chapter, createdAt: .now)
            try fresh.insert(db)
            for (i, memory) in memories.enumerated() {
                try db.execute(sql: "delete from story_moment where memory_id = ? and story_id = ?", arguments: [memory.rawValue, story.rawValue])
                try StoryMoment(storyID: fresh.id, memoryID: memory, order: i).insert(db)
            }
            return fresh
        }
    }

    private static func setPair(_ id: DuplicatePairID, _ status: PairStatus, in db: Database) throws {
        let decidedAt: Date? = status == .open ? nil : .now
        try db.execute(sql: "update duplicate_pair set status = ?, decided_at = ? where id = ?", arguments: [status.rawValue, decidedAt, id.rawValue])
    }

    public func derivedSpan(of story: StoryID) throws -> TimeRange {
        ChapterRepository.span(over: try members(of: story).map(\.range))
    }

    private static func clean(_ title: String?) -> String? {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }
}
