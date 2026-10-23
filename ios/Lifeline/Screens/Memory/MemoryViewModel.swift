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
    private(set) var span: MemorySpan?
    private(set) var session: Session?
    private(set) var ageText: String?
    private(set) var question: RelativeQuestion?
    private(set) var error: String?
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
            memory = try store.memories.fetch(memory.id) ?? memory
            people = try store.memories.people(of: memory.id)
            place = try store.memories.places(of: memory.id).first
            chapterTitle = try memory.chapterID.flatMap { try store.chapters.chapter(id: $0) }?.title
            span = try store.memories.spans(of: memory.id).first
            session = try span.flatMap { try store.sessions.fetchSegment($0.segmentID) }.flatMap { try store.sessions.fetch($0.sessionID) }
            let placedByAge = try store.memories.anchors(of: memory.id).contains { $0.relation == .age && $0.resolved }
            if placedByAge, let birth = try store.profile.ownerBirthDate(), let year = memory.range.earliest?.year, isGuess, year - birth.year >= 0 {
                ageText = "age ~\(year - birth.year)"
            } else {
                ageText = nil
            }
            question = try firstQuestion()
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
        if player.isPlaying { player.stop(); return }
        guard let span, let session else { error = "This memory has no audio."; return }
        do {
            try deps.activatePlayback()
            try player.play(url: try deps.audioURL(for: session), range: MsRange(start: span.startMs, end: span.endMs))
            error = nil
        } catch {
            self.error = "Could not play this memory: \(error.localizedDescription)"
        }
    }

    func answer(_ choice: RelativeQuestion.Choice) {
        guard let question else { return }
        do { try deps.actions.answer(question, with: choice); refresh() }
        catch { self.error = "Could not save that: \(error.localizedDescription)" }
    }

    func stop() { player.stop() }
}
