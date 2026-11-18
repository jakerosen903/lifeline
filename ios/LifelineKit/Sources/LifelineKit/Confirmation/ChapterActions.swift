import Foundation

/// What a person does to a chapter: rename it, say when it was, remove it (with undo), put a
/// moment in it and take one out. It also owns the write path for a moment's chapter tag, so
/// every tag change prunes the untitled chapter it may have emptied.
///
/// A tag is only ever the person's word. Nothing here tags a moment because its date falls in a
/// chapter's years, and a tag stays when the moment is dated outside them.
public struct ChapterActions: Sendable {
    public enum RenameResult: Equatable, Sendable { case renamed, empty, taken }

    let store: ExtractionStore

    public init(store: ExtractionStore) { self.store = store }

    /// Trims the title. Refused when nothing is left or another chapter already has that name
    /// (compared by `MatchKey`, so "maple street." is "Maple Street"). A chapter may take its own
    /// name again with new capitals. A chapter that no longer exists changes nothing.
    public func rename(_ id: ChapterID, to title: String) throws -> RenameResult {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = MatchKey.of(clean)
        guard !key.isEmpty else { return .empty }
        let taken = try store.chapters.chapters().contains { $0.id != id && MatchKey.of($0.title ?? "") == key }
        guard !taken else { return .taken }
        try store.chapters.rename(id, to: clean)
        return .renamed
    }

    /// The range from the sheet is the person's word, so it is stored as stated, whatever origin it came with.
    public func sayWhen(_ id: ChapterID, _ range: TimeRange) throws {
        var stated = range
        if stated.isPlaced { stated.origin = .stated }
        try store.chapters.setRange(id, stated)
    }

    /// The chapter goes; its moments and stories stay, with no chapter. Nil when there is no such chapter.
    public func remove(_ id: ChapterID) throws -> ChapterReceipt? {
        try store.chapters.remove(id)
    }

    /// Puts a removed chapter back, with the tags that are still free to take it. Harmless a second time.
    public func undoRemove(_ receipt: ChapterReceipt) throws {
        try store.chapters.restore(receipt)
    }

    /// Files a moment in a chapter, and removes the untitled chapter it left if that is now empty.
    /// Nil when the chapter or the memory is missing.
    @discardableResult
    public func add(_ memory: MemoryID, to chapter: ChapterID) throws -> Chapter? {
        guard let target = try store.chapters.chapter(id: chapter), try store.memories.fetch(memory) != nil else { return nil }
        try store.chapters.assign(memory: memory, toChapter: target.id)
        try store.chapters.deleteEmptyUntitled()
        return target
    }

    /// Files a moment in the chapter with this name (same `MatchKey`), making it when there is none.
    /// Nil when the name is empty or the memory is missing; nothing is created then.
    @discardableResult
    public func add(_ memory: MemoryID, toChapterNamed name: String) throws -> Chapter? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = MatchKey.of(clean)
        guard !key.isEmpty, try store.memories.fetch(memory) != nil else { return nil }
        let existing = try store.chapters.chapters().first { MatchKey.of($0.title ?? "") == key }
        let target = try existing ?? store.chapters.insertChapter(title: clean)
        return try add(memory, to: target.id)
    }

    /// The moment keeps no chapter. A named chapter left empty stays; an untitled one goes.
    public func takeOut(_ memory: MemoryID) throws {
        try store.chapters.assign(memory: memory, toChapter: nil)
        try store.chapters.deleteEmptyUntitled()
    }
}
