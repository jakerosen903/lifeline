import Foundation

/// Stories: what Keep does with a `story_ref`, what a title hint does, and what the person does
/// from a row's menu (M5). A memory is in at most one story; an emptied story is deleted.
extension CandidateActions {
    /// A new story around these memories, in the given order. Its chapter is the first member's.
    @discardableResult
    public func createStory(title: String?, containing memories: [MemoryID]) throws -> Story {
        let chapter = try memories.first.flatMap { try store.memories.fetch($0)?.chapterID }
        let story = try store.stories.insert(title: title, chapterID: chapter)
        for memory in memories { try addToStory(memory, story: story.id) }
        return try store.stories.story(id: story.id) ?? story
    }

    /// Appends the memory to the story. A memory already in another story is moved.
    public func addToStory(_ memory: MemoryID, story: StoryID) throws {
        if let current = try store.stories.story(of: memory) {
            if current.id == story { return }
            try store.stories.remove(memory: memory)
            try store.stories.deleteEmpty()
        }
        try store.stories.add(memory: memory, to: story)
    }

    public func moveToStory(_ memory: MemoryID, story: StoryID) throws {
        try addToStory(memory, story: story)
    }

    /// Takes the memory out; a story with nobody left in it is deleted.
    public func takeOutOfStory(_ memory: MemoryID) throws {
        try store.stories.remove(memory: memory)
        try store.stories.deleteEmpty()
    }

    public func renameStory(_ story: StoryID, title: String) throws {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw Error.emptyTitle }
        try store.stories.rename(story, title: clean)
    }

    /// The taken members become a new, untitled story. Taking none, or all of them, is refused.
    @discardableResult
    public func splitStory(_ story: StoryID, taking memories: [MemoryID]) throws -> Story {
        let members = try store.stories.members(of: story).map(\.id)
        let taken = members.filter { memories.contains($0) }
        guard !taken.isEmpty, taken.count < members.count else { throw Error.nothingToSplit }
        let fresh = try store.stories.insert(title: nil, chapterID: try store.stories.story(id: story)?.chapterID)
        for memory in taken {
            try store.stories.remove(memory: memory)
            try store.stories.add(memory: memory, to: fresh.id)
        }
        return fresh
    }

    /// What "One story" on a pair did, so undo can reverse exactly that.
    public struct GroupedPair: Sendable, Equatable {
        public var pair: DuplicatePair
        public var story: Story
        /// The memories that joined; the one already in the story is not listed.
        public var added: [MemoryID]
        /// True when the story was made for this pair.
        public var created: Bool
    }

    /// "Sounds like one story" on a pair: both memories in one story, a's if it has one, else
    /// b's, else a new one. Refused as stale when the pair was answered or a side is gone.
    @discardableResult
    public func groupPair(_ pair: DuplicatePair) throws -> GroupedPair {
        guard let current = try store.pairs.pair(id: pair.id), current.status == .open,
              let a = try store.memories.fetch(current.aMemoryID), let b = try store.memories.fetch(current.bMemoryID) else { throw Error.stale }
        let result: GroupedPair
        if let existing = try store.stories.story(of: a.id) {
            try addToStory(b.id, story: existing.id)
            result = GroupedPair(pair: current, story: existing, added: [b.id], created: false)
        } else if let existing = try store.stories.story(of: b.id) {
            try addToStory(a.id, story: existing.id)
            result = GroupedPair(pair: current, story: existing, added: [a.id], created: false)
        } else {
            let story = try createStory(title: nil, containing: [a.id, b.id])
            result = GroupedPair(pair: current, story: story, added: [a.id, b.id], created: true)
        }
        try store.pairs.setStatus(pair.id, .grouped)
        return result
    }

    /// Undo of "One story": the memories that joined leave again (a story made for the pair
    /// goes with them) and the pair is open once more.
    public func ungroupPair(_ grouped: GroupedPair) throws {
        for memory in grouped.added where try store.stories.story(of: memory)?.id == grouped.story.id {
            try store.stories.remove(memory: memory)
        }
        if grouped.created { try store.stories.delete(grouped.story.id) }
        try store.stories.deleteEmpty()
        if try store.pairs.pair(id: grouped.pair.id) != nil { try store.pairs.setStatus(grouped.pair.id, .open) }
    }

    /// Keep with a `story_ref`: the ref is always a story id (the queue mints one for every new
    /// raw ref), so the memory joins the story when its row exists and makes the row otherwise.
    func joinStory(_ memory: MemoryID, ref: String?) throws {
        guard let ref, !ref.isEmpty else { return }
        let id = StoryID(rawValue: ref)
        if try store.stories.story(id: id) == nil {
            try store.stories.insert(id: id, title: nil, chapterID: try store.memories.fetch(memory)?.chapterID)
        }
        try addToStory(memory, story: id)
    }

    /// A story title hint, accepted: the member's story takes the title, or a story is made
    /// around the member. Titles are the person's words, at most 8 of them.
    func acceptStoryHint(_ phrase: String, for memory: MemoryID) throws -> Story {
        let title = Self.storyTitle(from: phrase)
        if let story = try store.stories.story(of: memory) {
            try store.stories.rename(story.id, title: title)
            return try store.stories.story(id: story.id) ?? story
        }
        return try createStory(title: title, containing: [memory])
    }

    public static let storyTitleMaxWords = 8

    public static func storyTitle(from phrase: String) -> String {
        phrase.split(whereSeparator: \.isWhitespace).prefix(storyTitleMaxWords).joined(separator: " ")
    }
}
