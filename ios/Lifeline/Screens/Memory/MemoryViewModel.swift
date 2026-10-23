import Foundation
import LifelineKit

/// One memory: its range and evidence, its people and place, its words, and the question that
/// could narrow it.
@MainActor
@Observable
final class MemoryViewModel {
    private(set) var memory: Memory
    private(set) var people: [Person] = []
    private(set) var place: Place?
    private(set) var chapterTitle: String?
    /// Every telling, first telling first (M4.1). A telling told across a pause is one row: the
    /// spans that carry it on play after it (M5). `span` and `session` are the first.
    private(set) var spans: [(span: MemorySpan, session: Session)] = []
    private var continuations: [Int: [(span: MemorySpan, session: Session)]] = [:]
    private(set) var playingOrder: Int?
    private var playThrough: Task<Void, Never>?
    var span: MemorySpan? { spans.first?.span }
    var session: Session? { spans.first?.session }
    private(set) var ageText: String?
    private(set) var question: RelativeQuestion?
    private(set) var checkThis: [CheckThis] = []
    private var mentions: [Mention] = []
    private(set) var error: String?
    /// True once the memory was merged away or deleted; the screen closes itself.
    private(set) var isGone = false
    private(set) var birthDate: CivilDate?
    let player = SegmentPlayer()
    private let deps: Dependencies

    init(memory: Memory, deps: Dependencies) {
        self.memory = memory
        self.deps = deps
        refresh()
    }

    var rangeText: String { memory.range.displayText }
    var isGuess: Bool { memory.range.origin == .inferred }
    var evidence: String? { memory.range.evidenceText }
    var isPlaying: Bool { player.isPlaying }

    func refresh() {
        do {
            let store = deps.extractionStore
            guard let current = try store.memories.fetch(memory.id) else { isGone = true; return }
            memory = current
            birthDate = try store.profile.ownerBirthDate()
            people = try store.memories.people(of: memory.id)
            place = try store.memories.places(of: memory.id).first
            chapterTitle = try memory.chapterID.flatMap { try store.chapters.chapter(id: $0) }?.title
            let all: [(span: MemorySpan, session: Session)] = try store.memories.spans(of: memory.id).compactMap { span in
                guard let segment = try store.sessions.fetchSegment(span.segmentID), let session = try store.sessions.fetch(segment.sessionID) else { return nil }
                return (span, session)
            }
            spans = all.filter { $0.span.continuesOrder == nil }
            continuations = Dictionary(grouping: all.filter { $0.span.continuesOrder != nil }, by: { $0.span.continuesOrder! })
            let placedByAge = try store.memories.anchors(of: memory.id).contains { $0.relation == .age && $0.resolved }
            if placedByAge, let birth = try store.profile.ownerBirthDate(), let year = memory.range.earliest?.year, isGuess, year - birth.year >= 0 {
                ageText = "age ~\(year - birth.year)"
            } else {
                ageText = nil
            }
            question = try firstQuestion()
            mentions = try span.map { try store.people.mentions(in: $0.segmentID) } ?? []
            checkThis = CheckThisTags.tags(range: memory.range, mentions: mentions)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func firstQuestion() throws -> RelativeQuestion? {
        let store = deps.extractionStore
        let anchors = try store.memories.allAnchors()
        let all = try store.memories.allMemories()
        func ref(_ m: Memory) throws -> MemoryRef {
            let s = try store.memories.spans(of: m.id).first
            return MemoryRef(id: m.id, title: m.title, range: m.range,
                             primarySpan: MemoryRef.Span(segmentID: s?.segmentID ?? SegmentID(rawValue: ""), startMs: s?.startMs ?? 0, endMs: s?.endMs ?? 0))
        }
        let refs = try all.map(ref)
        var ids = Set<MemoryID>()
        for c in try store.chapters.collections(of: memory.id) { try store.chapters.members(of: c.id).forEach { ids.insert($0.id) } }
        if let chapter = memory.chapterID { try store.memories.memories(inChapter: chapter).forEach { ids.insert($0.id) } }
        for a in anchors where a.memoryID == memory.id { if let t = a.targetID { ids.insert(MemoryID(rawValue: t)) } }
        ids.remove(memory.id)
        return RelativeQuestions.question(for: try ref(memory), anchors: anchors, placed: refs.filter(\.range.isPlaced),
                                          siblings: refs.filter { ids.contains($0.id) }, birthDate: try store.profile.ownerBirthDate(), config: .default)
    }

    func togglePlayback() {
        guard let first = spans.first else { error = "This memory has no audio."; return }
        togglePlayback(of: first.span)
    }

    /// Plays one telling, then the spans that carry it on; a second tap on the same telling stops.
    func togglePlayback(of span: MemorySpan) {
        playThrough?.cancel()
        if player.isPlaying, playingOrder == span.order { player.stop(); playingOrder = nil; return }
        guard let telling = spans.first(where: { $0.span.order == span.order }) else { return }
        let queue = [telling] + (continuations[span.order] ?? [])
        playingOrder = span.order
        playThrough = Task { [weak self] in
            for part in queue {
                guard let self, !Task.isCancelled else { return }
                guard play(part) else { return }
                while player.isPlaying, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            }
            self?.playingOrder = nil
        }
    }

    private func play(_ part: (span: MemorySpan, session: Session)) -> Bool {
        do {
            try deps.activatePlayback()
            try player.play(url: try deps.audioURL(for: part.session), range: MsRange(start: part.span.startMs, end: part.span.endMs))
            error = nil
            return true
        } catch {
            self.error = "Could not play this memory: \(error.localizedDescription)"
            return false
        }
    }

    func isPlaying(_ span: MemorySpan) -> Bool { playingOrder == span.order && (player.isPlaying || playThrough != nil && !(playThrough?.isCancelled ?? true)) }

    func answer(_ choice: RelativeQuestion.Choice) {
        guard let question else { return }
        do { try deps.actions.answer(question, with: choice); refresh() }
        catch { self.error = "Could not save that: \(error.localizedDescription)" }
    }

    /// "Separate this telling": a later telling becomes its own memory again (M5).
    func separate(order: Int) {
        stop()
        do { _ = try deps.actions.separateTelling(memory.id, order: order); error = nil; refresh() }
        catch { self.error = "Could not separate that: \(error.localizedDescription)" }
    }

    /// "Tell me when": the person's own date, stored as said.
    func setStated(_ range: TimeRange) {
        do { try deps.actions.setStatedRange(memory.id, range); error = nil; refresh() }
        catch { self.error = "Could not save that: \(error.localizedDescription)" }
    }

    func mention(for tag: CheckThis) -> Mention? {
        guard case .person(_, let id) = tag else { return nil }
        return mentions.first { $0.id == id }
    }

    func stop() { playThrough?.cancel(); player.stop(); playingOrder = nil }
}
