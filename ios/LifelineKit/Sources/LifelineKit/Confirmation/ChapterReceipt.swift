import Foundation

/// What removing a chapter took away, so Undo can give it back in one write. The chapter row is
/// kept whole; the members and stories are the ids that pointed at it when it went.
public struct ChapterReceipt: Sendable, Equatable {
    public let chapter: Chapter
    public let members: [MemoryID]
    public let stories: [StoryID]

    public init(chapter: Chapter, members: [MemoryID], stories: [StoryID]) {
        self.chapter = chapter; self.members = members; self.stories = stories
    }
}
