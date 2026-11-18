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
    /// The title of the memory's chapter, trimmed; nil when it has no chapter or the chapter has no title (S6a).
    var chapterTitle: String? = nil
    /// The memory's chapter, named or not; the "Add to a chapter" sheet checks it.
    var chapterID: ChapterID? = nil
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

/// One stop on the spine: a moment or a story, with what `SpineLayout` says about it.
struct SpineRow: Identifiable, Equatable {
    enum Content: Equatable { case memory(MemoryRow), story(StoryRow) }
    let content: Content
    let stop: SpineLayout.Stop
    var id: String { stop.id }

    /// The moments this stop stands for: one, or a story's members.
    var momentCount: Int {
        switch content {
        case .memory: 1
        case .story(let story): story.members.count
        }
    }
}

/// Your story so far: one spine of dated moments and stories, collections, the shelf, the cards
/// still waiting, and the one question the app can ask. The home screen from M3 on.
@MainActor
@Observable
final class TimelineViewModel {
    private(set) var waiting: [Card] = []
    /// "Are these the same?": up to a few open pairs; a pair whose memory is gone is dropped (M5).
    private(set) var pairs: [PairRow] = []
    /// Dated loose moments and dated stories, whatever their chapter, in time order (S6a).
    private(set) var spine: [SpineRow] = []
    private(set) var collections: [CollectionRow] = []
    /// Loose moments with no year to show: unplaced, or placed by one end only.
    private(set) var shelf: [MemoryRow] = []
    /// Visible facts, feelings and goals: not moments, so never on the shelf or in a chapter, and no rows here. They
    /// live on You and on their own pages; Timeline only counts them for its summary and, with no tag filter, its empty state (S3).
    private(set) var aboutCount = 0
    /// Stories with no year to lay out: no member is dated (M5, S6a).
    private(set) var shelfStories: [StoryRow] = []
    private(set) var allStories: [Story] = []
    /// Chapters with a name, for "Add to a chapter…". An unnamed chapter is not offered: the person has no word for it.
    private(set) var namedChapters: [Chapter] = []
    /// Story rows the person opened.
    var expandedStories: Set<StoryID> = []
    private(set) var floatingCount = 0
    private(set) var question: RelativeQuestion?
    private(set) var questionRow: MemoryRow?
    private(set) var summary = ""
    private(set) var error: String?
    /// The Hidden filter: show memories hidden from the timeline too.
    var showHidden = false { didSet { refresh() } }
    /// Domains (M7): only what carries this free-text tag; nil shows everything.
    var tagFilter: String? { didSet { refresh() } }
    private(set) var allTags: [String] = []
    /// What is still sorting (M6); polled every second only while there is something to say.
    /// The view reads `sorting`, which changes only when the words or the buttons do, so the
    /// row is not rebuilt every time the worker's activity flips.
    struct SortingPresentation: Equatable { var line: String?; var needsKey: Bool; var canRetry: Bool }
    private(set) var sorting = SortingPresentation(line: nil, needsKey: false, canRetry: false)
    @ObservationIgnored private var sortingStatus: SortingStatus = .empty
    @ObservationIgnored private var sortingPoll: Task<Void, Never>?
    var sortingLine: String? { sorting.line }
    private var skippedQuestions: Set<MemoryID> = []

    let home: HomeViewModel
    /// The waiting cards of every session as one queue, acted on with the same calls as the live session.
    let flow: CardFlow
    var cards: CardHandler { flow.handler }
    let deps: Dependencies

    init(deps: Dependencies, home: HomeViewModel) {
        self.deps = deps
        self.home = home
        flow = CardFlow(deps: deps)
        refresh()
        flow.onAutoClose = { [weak self] in self?.refresh() }
        // New pairs from the pass become cards without a relaunch.
        Task { [weak self] in
            await deps.duplicates.setOnFinished { written in
                guard written > 0 else { return }
                Task { @MainActor in self?.refresh() }
            }
        }
        deps.reporter.onChange = { [weak self] in Task { @MainActor in self?.refreshSorting() } }
    }

    /// Re-reads the status line; while something is sorting, keeps re-reading every second.
    func refreshSorting() {
        let status = deps.sortingStatus()
        sortingStatus = status
        let presentation = SortingPresentation(line: status.line(), needsKey: status.needsKey, canRetry: status.canRetry)
        if presentation != sorting { sorting = presentation }
        if status.isEmpty || status.canRetry || status.needsKey {
            sortingPoll?.cancel(); sortingPoll = nil
            return
        }
        guard sortingPoll == nil else { return }
        sortingPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refreshSorting()
                if self?.sortingStatus.isEmpty ?? true { self?.refresh() }
            }
        }
    }

    /// "Try again" on "Not sorting right now".
    func tryAgain() { deps.worker.requestStart(); refreshSorting() }

    /// What the page holds; zero shows the empty state. With a tag filter on, only the moments that match count.
    var memoryCount: Int {
        spine.reduce(0) { $0 + $1.momentCount } + collections.reduce(0) { $0 + $1.members.count }
            + shelf.count + shelfStories.reduce(0) { $0 + $1.members.count } + (tagFilter == nil ? aboutCount : 0)
    }

    // MARK: - Loading

    func refresh() {
        do {
            let store = deps.extractionStore
            let tagged = try tagFilter.map { try store.tags.elements(.memory, tagged: $0) }
            let listed = try (showHidden ? store.memories.allMemories() : store.memories.visibleMemories()).filter { !$0.isFloating }
            // The menu offers only tags a moment carries: a tag only on facts would filter to an empty Timeline (S3).
            allTags = TimelineSummary.menuTags(try store.tags.tagsByElement(.memory), moments: listed)
            // A filter whose tag no moment carries any more (the last one was hidden or deleted) turns itself off;
            // the menu that could clear it may be gone. Setting it reads again, so this pass ends here.
            if tagFilter != TimelineSummary.filter(tagFilter, offered: allTags) { tagFilter = nil; return }
            // Only moments are on the timeline; the rest are counted, never drawn (M7, S3). The count is of visible
            // ones, whatever the filter: Timeline cannot show a hidden fact, so it must not count one.
            aboutCount = TimelineSummary.thingsAboutYourLife(listed)
            let all = listed.filter { $0.isMoment && (tagged?.contains($0.id.rawValue) ?? true) }
            let birth = try store.profile.ownerBirthDate()
            let allChapters = try store.chapters.chapters()
            namedChapters = allChapters.filter { $0.name != nil }
            let chapterTitles = Self.chapterTitles(allChapters)
            let rows = Dictionary(uniqueKeysWithValues: try all.map { ($0.id, try row(for: $0, birth: birth, chapterTitles: chapterTitles)) })
            let allCollections = try store.chapters.collections()
            var inCollection = Set<MemoryID>()
            collections = try allCollections.compactMap { collection in
                let members = try store.chapters.members(of: collection.id).compactMap { rows[$0.id] }
                members.forEach { inCollection.insert($0.id) }
                return members.isEmpty ? nil : CollectionRow(collection: collection, span: try store.chapters.derivedSpan(of: collection.id), members: members)
            }
            // A story renders once, on the spine or on the shelf, members folded under it; a
            // story with one visible member is not a group and its member stays a plain row. A
            // moment can sit in its story and in a collection (builder call 6).
            allStories = try store.stories.stories()
            var inStory = Set<MemoryID>()
            let storyRows: [StoryRow] = try allStories.compactMap { story in
                let members = try store.stories.members(of: story.id).compactMap { rows[$0.id] }
                guard members.count >= 2 else { return nil }
                members.forEach { inStory.insert($0.id) }
                return StoryRow(story: story, members: members, span: ChapterRepository.span(over: members.map(\.memory.range)))
            }
            let loose = all.filter { !inCollection.contains($0.id) && !inStory.contains($0.id) }.compactMap { rows[$0.id] }
            // The spine needs a year to show for every stop. A range that is unplaced, or placed by one
            // end only ("before 2004" with no start), has none: it goes to the shelf, so nothing disappears.
            let entries = loose.map(SpineEntry.init(memory:)) + storyRows.map(SpineEntry.init(story:))
            spine = Self.spine(of: entries.filter(\.range.isDated), birthYear: birth?.year)
            shelf = loose.filter { !$0.memory.range.isDated }
            shelfStories = entries.compactMap { entry in
                guard case .story(let story) = entry.content, !entry.range.isDated else { return nil }
                return story
            }
            floatingCount = try store.memories.visibleMemories().filter { $0.isFloating && !$0.range.isPlaced }.count

            let years = all.flatMap { [$0.range.earliest?.year, $0.range.latest?.year].compactMap { $0 } }

            waiting = try waitingCards()
            pairs = try openPairs()
            refreshSorting()
            (question, questionRow) = try firstQuestion(rows: rows, birth: birth)
            summary = TimelineSummary.text(memories: all.count, firstYear: years.min(), things: aboutCount, tagFiltered: tagFilter != nil)
            error = nil
        } catch {
            self.error = "Could not load your story: \(error.localizedDescription)"
        }
    }

    /// Chapter titles by chapter, read once a refresh: trimmed, and only those with words in them.
    private static func chapterTitles(_ chapters: [Chapter]) -> [ChapterID: String] {
        var titles: [ChapterID: String] = [:]
        for chapter in chapters {
            if let title = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { titles[chapter.id] = title }
        }
        return titles
    }

    private func row(for memory: Memory, birth: CivilDate?, chapterTitles: [ChapterID: String]) throws -> MemoryRow {
        let store = deps.extractionStore
        let kind = memory.kind
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
                         checkThis: CheckThisTags.tags(range: memory.isMoment ? memory.range : .unplaced, mentions: try span.map { try store.people.mentions(in: $0.segmentID) } ?? []),
                         storyID: try store.stories.story(of: memory.id)?.id,
                         chapterTitle: memory.chapterID.flatMap { chapterTitles[$0] },
                         chapterID: memory.chapterID)
    }

    // MARK: - The spine

    /// A moment or a story before it is laid out: the range it sits on the spine by, and its creation time for ties.
    private struct SpineEntry {
        let content: SpineRow.Content
        /// Unique across moments and stories: the stop's id.
        let id: String
        let range: TimeRange
        let createdAt: Date

        init(memory row: MemoryRow) {
            content = .memory(row); id = "memory-\(row.id.rawValue)"; range = row.memory.range; createdAt = row.memory.createdAt
        }

        /// A story lays out by `SpineLayout.storyRange`, not by its derived span (decision 8): only that
        /// range knows whether every member reads as said.
        init(story row: StoryRow) {
            content = .story(row); id = "story-\(row.id.rawValue)"
            range = SpineLayout.storyRange(members: row.members.map(\.memory.range)); createdAt = row.story.createdAt
        }
    }

    /// `entries` in time order, each with its stop. Every entry must be dated.
    private static func spine(of entries: [SpineEntry], birthYear: Int?) -> [SpineRow] {
        let ordered = entries.sorted(by: byTime)
        let stops = SpineLayout.stops(for: ordered.map { (id: $0.id, range: $0.range) }, birthYear: birthYear)
        let contents = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0.content) })
        return stops.compactMap { stop in contents[stop.id].map { SpineRow(content: $0, stop: stop) } }
    }

    /// The likely start, else the earliest; ties and undated entries by creation, undated last.
    private static func byTime(_ a: SpineEntry, _ b: SpineEntry) -> Bool {
        let ka = a.range.likelyStart ?? a.range.earliest, kb = b.range.likelyStart ?? b.range.earliest
        switch (ka, kb) {
        case (let x?, let y?): return x != y ? x < y : a.createdAt < b.createdAt
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.createdAt < b.createdAt
        }
    }

    /// Every pending card across sessions, newest session first, plus names still open. A kept
    /// card open on screen stays as it is.
    private func waitingCards() throws -> [Card] {
        let store = deps.extractionStore
        let candidates = store.candidates
        let pending = try store.sessions.listSessions().flatMap { try candidates.pending(in: $0.id) }
        flow.reload(CardQueue.waiting(pending: pending,
                                      segmentMemories: { (try? candidates.candidates(for: $0)) ?? [] },
                                      candidate: { try? candidates.fetch($0) }))
        var cards = flow.cards
        let shown = Set(cards.flatMap(\.withFollowUps).compactMap { if case .whoIsThis(_, let text) = $0 { PeopleRepository.normalize(text) } else { nil } })
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
                         primarySpan: MemoryRef.Span(segmentID: span?.segmentID ?? SegmentID(rawValue: ""), startMs: span?.startMs ?? 0, endMs: span?.endMs ?? 0), kind: memory.kind)
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

    // Each action changes the queue as the live session does, then re-reads the store; the
    // rebuilt queue keeps the open kept card as it is on screen.
    func accept(_ card: Card) { if flow.accept(card) { refresh() } }
    func change(_ card: Card) { if let memory = flow.change(card) { refresh(); changing = memory } }
    func dismiss(_ card: Card) { if flow.dismiss(card) { refresh() } }
    /// The page a checked entity or person chip opened (M7).
    var openedEntity: Entity?
    func followUp(_ kept: KeptCard, _ card: Card, as type: EntityType?) { if flow.followUp(kept, card, as: type) { refresh() } }
    func resolveFollowUp(_ kept: KeptCard, _ card: Card, _ choice: MentionChoice) { if flow.resolveFollowUp(kept, card, choice) { refresh() } }
    func declineFollowUp(_ kept: KeptCard, _ card: Card) { if flow.declineFollowUp(kept, card) { refresh() } }
    func keptDone(_ kept: KeptCard) { flow.keptDone(kept); refresh() }
    /// A checked entity or person chip, tapped again: its page.
    func open(_ followUp: Card) { openedEntity = flow.page(for: followUp) }
    func undo() { if flow.undo() { refresh() } }
    func undoMerge() { if flow.undoMerge() { refresh() } }
    func undoKeptClose() { if flow.undoKeptClose() { refresh() } }
    func sameStory(_ card: Card, into targets: [MemoryID]) { if flow.sameStory(card, into: targets) { refresh() } }

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

    // MARK: - Chapters

    func addToChapter(_ memory: MemoryID, chapter: ChapterID) {
        attempt("Could not add that to a chapter") { _ = try ChapterActions(store: deps.extractionStore).add(memory, to: chapter) }
    }

    /// An empty or spaces-only name writes nothing; a name that matches a chapter in other capitals reuses it (kit).
    func addToChapter(_ memory: MemoryID, named name: String) {
        attempt("Could not add that to a chapter") { _ = try ChapterActions(store: deps.extractionStore).add(memory, toChapterNamed: name) }
    }

    func takeOutOfChapter(_ memory: MemoryID) {
        attempt("Could not take that out of its chapter") { try ChapterActions(store: deps.extractionStore).takeOut(memory) }
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
    func resolve(_ card: Card, _ choice: MentionChoice) { if flow.resolve(card, choice) { refresh() } }

    func addToCollection(_ memory: MemoryID, title: String) {
        do { _ = try deps.actions.addToCollection(memory, titled: title); refresh() }
        catch { self.error = "Could not add to a collection: \(error.localizedDescription)" }
    }

    var existingCollectionTitles: [String] { collections.map(\.collection.title) }

}
