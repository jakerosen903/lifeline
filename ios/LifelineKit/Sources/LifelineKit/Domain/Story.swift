import Foundation

/// Related moments of one thread ("the summer of the blue door"). Untitled until the person
/// names it or keeps a hint built from their words. A memory belongs to at most one story.
public struct Story: Codable, Sendable, Equatable, Identifiable {
    public var id: StoryID
    public var title: String?
    public var chapterID: ChapterID?
    public var createdAt: Date

    public init(id: StoryID, title: String?, chapterID: ChapterID?, createdAt: Date) {
        self.id = id; self.title = title; self.chapterID = chapterID; self.createdAt = createdAt
    }
}

public struct StoryMoment: Codable, Sendable, Equatable {
    public var storyID: StoryID
    public var memoryID: MemoryID
    public var order: Int

    public init(storyID: StoryID, memoryID: MemoryID, order: Int) {
        self.storyID = storyID; self.memoryID = memoryID; self.order = order
    }
}
