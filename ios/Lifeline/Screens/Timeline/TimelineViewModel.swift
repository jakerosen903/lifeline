import Foundation
import LifelineKit

/// One memory as the timeline shows it.
struct MemoryRow: Identifiable, Equatable, Hashable {
    let memory: Memory
    let kind: MemoryKind
    let rangeText: String
    let isGuess: Bool
    let ageText: String?
    let people: [String]
    let place: String?
    let durationText: String
    /// Details keeping did not settle: an inferred range, names still open.
    let checkThis: [CheckThis]
    /// The story this memory belongs to, if any (M5).
    var storyID: StoryID? = nil
    var id: MemoryID { memory.id }

    func hash(into hasher: inout Hasher) { hasher.combine(memory.id) }

    /// Range, age and people in one line, for the row's accessibility label and the summary.
    var subtitle: String {
        var parts = [rangeText]
        if let ageText { parts.append(ageText) }
        if !people.isEmpty { parts.append(people.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

struct CollectionRow: Identifiable, Equatable {
    let collection: Collection
    let span: TimeRange
    let members: [MemoryRow]
    var id: CollectionID { collection.id }
}

/// Related moments as one row: titled by the person, or "{first} + {n} more" meanwhile (M5).
struct StoryRow: Identifiable, Equatable {
    let story: Story
    let members: [MemoryRow]
    let span: TimeRange
    var id: StoryID { story.id }
    var title: String { story.title ?? "\(members[0].memory.title) + \(members.count - 1) more" }
    var isPlaced: Bool { span.isPlaced }
}

struct ChapterRow: Identifiable, Equatable {
    let chapter: Chapter
    let memories: [MemoryRow]
    var stories: [StoryRow] = []
    var id: ChapterID { chapter.id }
    var title: String { chapter.title ?? "Untitled chapter" }
}

/// Your story so far: chapters as structure, memories as honest bands, collections, the shelf,
/// the cards still waiting, and the one question the app can ask. The home screen from M3 on.
@MainActor
@Observable
final class TimelineViewModel {
    private(set) var waiting: [Card] = []
    /// "Are these the same?": up to a few open pairs; a pair whose memory is gone is dropped (M5).
    private(set) var pairs: [PairRow] = []
    private(set) var chapters: [ChapterRow] = []
    private(set) var collections: [CollectionRow] = []
    private(set) var unchaptered: [MemoryRow] = []
    private(set) var shelf: [MemoryRow] = []
    /// Stories outside any chapter with a dated member, and stories with none (M5).
    private(set) var unchapteredStories: [StoryRow] = []
    private(set) var shelfStories: [StoryRow] = []
    private(set) var allStories: [Story] = []
    /// Story rows the person opened.
    var expandedStories: Set<StoryID> = []
    private(set) var floatingCount = 0
    private(set) var question: RelativeQuestion?
    private(set) var questionRow: MemoryRow?
    private(set) var axis: ClosedRange<Int>?
    private(set) var summary = ""
    private(set) var error: String?
    /// The Hidden filter: show memories hidden from the timeline too.
    var showHidden = false { didSet { refresh() } }
    private var skippedQuestions: Set<MemoryID> = []

    let home: HomeViewModel
    let cards: CardHandler
    let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
        home = HomeViewModel(deps: deps)
        cards = CardHandler(deps: deps)
        refresh()
        // New pairs from the pass become cards without a relaunch.
        Task { [weak self] in
            await deps.duplicates.setOnFinished { written in
                guard written > 0 else { return }
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    var memoryCount: Int {
        chapters.reduce(0) { $0 + $1.memories.count + $1.stories.reduce(0) { $0 + $1.members.count } } + collections.reduce(0) { $0 + $1.members.count }
            + unchaptered.count + shelf.count + (unchapteredStories + shelfStories).reduce(0) { $0 + $1.members.count }
    }

    // MARK: - Loading

    func refresh() {
        do {
            let store = deps.extractionStore
            let all = try (showHidden ? store.memories.allMemories() : store.memories.visibleMemories()).filter { !$0.isFloating }
            let birth = try store.profile.ownerBirthDate()
            let rows = Dictionary(uniqueKeysWithValues: try all.map { ($0.id, try row(for: $0, birth: birth)) })
            let allCollections = try store.chapters.collections()
            var inCollection = Set<MemoryID>()
            collections = try allCollections.compactMap { collection in
                let members = try store.chapters.members(of: collection.id).compactMap { rows[$0.id] }
                members.forEach { inCollection.insert($0.id) }
                return members.isEmpty ? nil : CollectionRow(collection: collection, span: try store.chapters.derivedSpan(of: collection.id), members: members)
            }
            // A story renders once, in its chapter or on the timeline, members folded under it; a
            // story with one visible member is not a group and its member stays a plain row.
            allStories = try store.stories.stories()
            var inStory = Set<MemoryID>()
            let storyRows: [StoryRow] = try allStories.compactMap { story in
                let members = try store.stories.members(of: story.id).compactMap { rows[$0.id] }.filter { !inCollection.contains($0.id) }
                guard members.count >= 2 else { return nil }
                members.forEach { inStory.insert($0.id) }
                return StoryRow(story: story, members: members, span: ChapterRepository.span(over: members.map(\.memory.range)))
            }
            let loose = all.filter { !inCollection.contains($0.id) && !inStory.contains($0.id) }.compactMap { rows[$0.id] }
            chapters = try store.chapters.chapters().map { chapter in
                ChapterRow(chapter: chapter, memories: loose.filter { $0.memory.chapterID == chapter.id && $0.memory.range.isPlaced }.sorted(by: Self.byTime),
                           stories: storyRows.filter { $0.story.chapterID == chapter.id && $0.isPlaced })
            }
            unchaptered = loose.filter { $0.memory.chapterID == nil && $0.memory.range.isPlaced }.sorted(by: Self.byTime)
            let chapterIDs = Set(chapters.map(\.id))
            unchapteredStories = storyRows.filter { row in row.isPlaced && !(row.story.chapterID.map { chapterIDs.contains($0) } ?? false) }
            shelfStories = storyRows.filter { !$0.isPlaced }
            shelf = loose.filter { !$0.memory.range.isPlaced }
            floatingCount = try store.memories.visibleMemories().filter { $0.isFloating && !$0.range.isPlaced }.count

            let years = all.flatMap { [$0.range.earliest?.year, $0.range.latest?.year].compactMap { $0 } }
            axis = years.isEmpty ? nil : (years.min()! ... max(years.max()!, Calendar.current.component(.year, from: .now)))

            waiting = try waitingCards()
            pairs = try openPairs()
            (question, questionRow) = try firstQuestion(rows: rows, birth: birth)
            summary = Self.summaryText(memories: all.count, chapters: chapters.count, firstYear: years.min())
            error = nil
        } catch {
            self.error = "Could not load your story: \(error.localizedDescription)"
        }
    }

    private func row(for memory: Memory, birth: CivilDate?) throws -> MemoryRow {
        let store = deps.extractionStore
        let kind = memory.createdFromCandidateID.flatMap { try? store.candidates.fetch($0) }.flatMap { CandidatePayload.memory($0) }?.kindOrDefault ?? .other
        let span = try store.memories.spans(of: memory.id).first
        var age: String?
        // Only when an age anchor is what placed it; a relative guess says nothing about age.
        let placedByAge = try store.memories.anchors(of: memory.id).contains { $0.relation == .age && $0.resolved }
        if placedByAge, let birth, let year = memory.range.earliest?.year, memory.range.origin == .inferred {
            let a = year - birth.year
            if a >= 0 { age = "age ~\(a)" }
        }
        return MemoryRow(memory: memory, kind: kind, rangeText: memory.range.displayText, isGuess: memory.range.origin == .inferred, ageText: age,
                         people: try store.memories.people(of: memory.id).map(\.displayName),
                         place: try store.memories.places(of: memory.id).first?.nameText,
                         durationText: span.map { Format.duration(ms: $0.endMs - $0.startMs) } ?? "",
                         checkThis: CheckThisTags.tags(range: memory.range, mentions: try span.map { try store.people.mentions(in: $0.segmentID) } ?? []),
                         storyID: try store.stories.story(of: memory.id)?.id)
    }

    private static func byTime(_ a: MemoryRow, _ b: MemoryRow) -> Bool {
        let ka = a.memory.range.likelyStart ?? a.memory.range.earliest, kb = b.memory.range.likelyStart ?? b.memory.range.earliest
        switch (ka, kb) {
        case (let x?, let y?): return x != y ? x < y : a.memory.createdAt < b.memory.createdAt
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.memory.createdAt < b.memory.createdAt
        }
    }

    private static func summaryText(memories: Int, chapters: Int, firstYear: Int?) -> String {
        var parts = ["\(memories) \(memories == 1 ? "memory" : "memories")"]
        if chapters > 0 { parts.append("\(chapters) \(chapters == 1 ? "chapter" : "chapters")") }
        if let firstYear { parts.append("\(firstYear) → now") }
        return parts.joined(separator: " · ")
    }

    /// Every pending card across sessions, newest session first, plus names still open.
    private func waitingCards() throws -> [Card] {
        let store = deps.extractionStore
        var cards: [Card] = []
        for session in try store.sessions.listSessions() {
            cards += CardQueue.waitingCards(pending: try store.candidates.pending(in: session.id)) { (try? store.candidates.fetch($0))?.status }
        }
        let shown = Set(cards.compactMap { if case .whoIsThis(_, let text) = $0 { PeopleRepository.normalize(text) } else { nil } })
        var seen = shown
        cards += try store.people.mentions(status: .unresolved)
            .filter { seen.insert(PeopleRepository.normalize($0.text)).inserted }
            .map(Card.init)
        return cards
    }

    /// The open pairs, oldest first, as far as both memories still exist and are shown.
    private func openPairs() throws -> [PairRow] {
        let store = deps.extractionStore
        return try store.pairs.open(limit: PairConfig.default.shownAtOnce * 2).compactMap { pair in
            guard let a = try store.memories.fetch(pair.aMemoryID), let b = try store.memories.fetch(pair.bMemoryID),
                  showHidden || (!a.hiddenFromTimeline && !b.hiddenFromTimeline) else { return nil }
            return PairRow(pair: pair, a: a, b: b, aRecordedAt: try firstTold(a.id), bRecordedAt: try firstTold(b.id))
        }.prefix(PairConfig.default.shownAtOnce).map { $0 }
    }

    private func firstTold(_ memory: MemoryID) throws -> Date? {
        let store = deps.extractionStore
        guard let span = try store.memories.spans(of: memory).first, let segment = try store.sessions.fetchSegment(span.segmentID) else { return nil }
        return try store.sessions.fetch(segment.sessionID)?.startedAt
    }

    // MARK: - The question

    private func firstQuestion(rows: [MemoryID: MemoryRow], birth: CivilDate?) throws -> (RelativeQuestion?, MemoryRow?) {
        let store = deps.extractionStore
        let anchors = try store.memories.allAnchors()
        let all = try store.memories.allMemories()
        let refs = try all.map { try ref($0) }
        let placed = refs.filter(\.range.isPlaced)
        for memory in all where !memory.isFloating && !memory.range.isConfirmed && !skippedQuestions.contains(memory.id) {
            let me = try ref(memory)
            let mates = try siblings(of: memory, anchors: anchors, refs: refs)
            if let q = RelativeQuestions.question(for: me, anchors: anchors, placed: placed, siblings: mates, birthDate: birth, config: .default) {
                return (q, rows[memory.id])
            }
        }
        return (nil, nil)
    }

    /// Collection and chapter mates, plus whatever this memory's anchors point at.
    private func siblings(of memory: Memory, anchors: [Anchor], refs: [MemoryRef]) throws -> [MemoryRef] {
        let store = deps.extractionStore
        var ids = Set<MemoryID>()
        for collection in try store.chapters.collections(of: memory.id) {
            try store.chapters.members(of: collection.id).forEach { ids.insert($0.id) }
        }
        if let chapter = memory.chapterID { try store.memories.memories(inChapter: chapter).forEach { ids.insert($0.id) } }
        for anchor in anchors where anchor.memoryID == memory.id {
            if let target = anchor.targetID { ids.insert(MemoryID(rawValue: target)) }
        }
        ids.remove(memory.id)
        return refs.filter { ids.contains($0.id) }
    }

    private func ref(_ memory: Memory) throws -> MemoryRef {
        let span = try deps.extractionStore.memories.spans(of: memory.id).first
        return MemoryRef(id: memory.id, title: memory.title, range: memory.range,
                         primarySpan: MemoryRef.Span(segmentID: span?.segmentID ?? SegmentID(rawValue: ""), startMs: span?.startMs ?? 0, endMs: span?.endMs ?? 0))
    }

    func answer(_ choice: RelativeQuestion.Choice) {
        guard let question else { return }
        do {
            try deps.actions.answer(question, with: choice)
            refresh()
        } catch {
            self.error = "Could not save that: \(error.localizedDescription)"
        }
    }

    func keepForNow() {
        if let id = question?.memoryID { skippedQuestions.insert(id) }
        refresh()
    }

    // MARK: - Cards and editing

    var changing: Memory?
    var deleteTarget: MemoryRow?

    func accept(_ card: Card) { if cards.accept(card) { refresh() } }
    func change(_ card: Card) { if let memory = cards.keep(card) { refresh(); changing = memory } }
    func dismiss(_ card: Card) { if cards.dismiss(card) { refresh() } }
    func undo() { if cards.undo() != nil { refresh() } }
    func undoMerge() { if cards.undoMerge() != nil { refresh() } }
    func sameStory(_ card: Card, into targets: [MemoryID]) { if cards.sameStory(card, into: targets) { refresh() } }

    /// A pair answered: Same story / One story (true) or Keep separate (false).
    func answerPair(_ row: PairRow, same: Bool) {
        let done = same ? (row.pair.verdict == .sameStory ? cards.groupPair(row.pair) : cards.samePair(row.pair)) : cards.separatePair(row.pair)
        if done { refresh() }
    }

    func undoPair() { if cards.undoPair() { refresh() } }

    // MARK: - Stories (M5)

    func toggleStory(_ id: StoryID) {
        if expandedStories.contains(id) { expandedStories.remove(id) } else { expandedStories.insert(id) }
    }

    func renameStory(_ id: StoryID, title: String) {
        attempt("Could not rename the story") { try deps.actions.renameStory(id, title: title) }
    }

    func splitStory(_ id: StoryID, taking members: [MemoryID]) {
        attempt("Could not split the story") { _ = try deps.actions.splitStory(id, taking: members) }
    }

    func moveToStory(_ memory: MemoryID, story: StoryID) {
        attempt("Could not move that") { try deps.actions.moveToStory(memory, story: story) }
    }

    func takeOutOfStory(_ memory: MemoryID) {
        attempt("Could not take that out") { try deps.actions.takeOutOfStory(memory) }
    }

    /// Stories a memory could move to: every other one.
    func otherStories(for memory: MemoryRow) -> [Story] { allStories.filter { $0.id != memory.storyID } }

    // MARK: - The "…" menu on a row (every long-press has a visible alternative)

    func hide(_ memory: MemoryID) {
        attempt("Could not hide that") { try deps.actions.setHidden(memory, true) }
    }

    /// "Add a date" on a shelf row.
    func setStated(_ memory: MemoryID, _ range: TimeRange) {
        attempt("Could not save that") { try deps.actions.setStatedRange(memory, range) }
    }

    func setExcluded(_ memory: MemoryID, _ excluded: Bool) {
        attempt("Could not change that") { try deps.actions.setExcluded(memory, excluded) }
    }

    /// After the confirmation: the memory and its spans, people and anchors go; the recording stays.
    func delete(_ memory: MemoryID) {
        attempt("Could not delete that") { try deps.extractionStore.memories.delete(memory) }
    }

    private func attempt(_ message: String, _ work: () throws -> Void) {
        do { try work(); error = nil; refresh() } catch { self.error = "\(message): \(error.localizedDescription)" }
    }
    func resolve(_ card: Card, _ choice: MentionChoice) { if cards.resolve(card, choice) { refresh() } }

    func newChapter(for memory: MemoryID, title: String?) {
        do { _ = try deps.actions.createChapter(title: title, containing: memory); refresh() }
        catch { self.error = "Could not make a chapter: \(error.localizedDescription)" }
    }

    func addToCollection(_ memory: MemoryID, title: String) {
        do { _ = try deps.actions.addToCollection(memory, titled: title); refresh() }
        catch { self.error = "Could not add to a collection: \(error.localizedDescription)" }
    }

    var existingCollectionTitles: [String] { collections.map(\.collection.title) }

    func sessionEnded() {
        home.sessionEnded()
        refresh()
    }
}
