import Foundation
import LifelineKit

/// Change… on a memory: the title, who was there, when it was. The quote is never edited.
/// "Which part of the recording" and "Just tell me" are listed but wait for M5 and the interviewer.
@MainActor
@Observable
final class ChangeViewModel {
    private(set) var memory: Memory
    private(set) var people: [Person] = []
    private(set) var choices: [Person] = []
    var draftTitle: String
    var newName = ""
    private(set) var error: String?
    let when: MemoryViewModel
    /// After "Same as another memory…": the title it merged into, while Undo is offered.
    private(set) var mergedInto: String?
    private var mergeReceipt: MergeReceipt?
    /// Set when this memory no longer exists (merged away): the sheet's owner closes.
    private(set) var isGone = false
    /// "Which part of the recording" (M6): each telling's spans with their segments' words.
    struct Part: Identifiable, Equatable {
        let span: MemorySpan
        let words: [Word]
        var id: Int { span.order }
        /// The words the span covers now, as indexes into `words`.
        var covered: ClosedRange<Int>? {
            guard let first = words.firstIndex(where: { $0.endMs > span.startMs }), let last = words.lastIndex(where: { $0.startMs < span.endMs }), first <= last else { return nil }
            return first...last
        }
        var title: String { span.continuesOrder == nil ? (span.order == 0 ? "First telling" : "Telling \(span.order + 1)") : "Continued" }
    }
    private(set) var parts: [Part] = []
    /// After a trim, while the sheet is open: what it did, with Undo.
    private(set) var trimmedNotice: String?
    private var trimReceipt: TrimReceipt?
    private let includeHidden: Bool
    let deps: Dependencies

    init(memory: Memory, deps: Dependencies, includeHidden: Bool = false) {
        self.memory = memory
        self.deps = deps
        self.includeHidden = includeHidden
        draftTitle = memory.title
        when = MemoryViewModel(memory: memory, deps: deps)
        refresh()
    }

    // MARK: - Same as another memory… (M4.1)

    /// The nearest memories, hidden ones only when the timeline is showing them. Never this one.
    func pickerMatches() -> [MemoryMatch] {
        let text = MemoryMatcher.text(title: memory.title, quote: memory.summaryQuote)
        return (try? deps.matcher.picker(for: text, excluding: [memory.id], includeHidden: includeHidden)) ?? []
    }

    func merge(into target: MemoryID) {
        do {
            let receipt = try deps.actions.merge(memory.id, into: target)
            mergeReceipt = receipt
            mergedInto = receipt.targetTitle
            isGone = true
            error = nil
        } catch {
            self.error = "Could not merge: \(error.localizedDescription)"
        }
    }

    func undoMerge() {
        guard let receipt = mergeReceipt else { return }
        do {
            try deps.actions.unmerge(receipt)
            mergeReceipt = nil
            mergedInto = nil
            isGone = false
            error = nil
            refresh()
        } catch {
            self.error = "That can't be undone any more: \(error.localizedDescription)"
        }
    }

    // MARK: - Which part of the recording (M6)

    func trim(order: Int, startWord: Int, endWord: Int) {
        do {
            trimReceipt = try deps.actions.trimTelling(memory.id, order: order, startWord: startWord, endWord: endWord)
            let n = endWord - startWord + 1
            trimmedNotice = "Now \(n == 1 ? "1 word" : "\(n) words") of the recording."
            error = nil
            refresh()
        } catch {
            self.error = "Could not change that: \(error.localizedDescription)"
        }
    }

    func undoTrim() {
        guard let receipt = trimReceipt else { return }
        do {
            try deps.actions.undoTrim(receipt)
            trimReceipt = nil
            trimmedNotice = nil
            error = nil
            refresh()
        } catch {
            self.error = "That can't be undone any more: \(error.localizedDescription)"
        }
    }

    /// "What is this?" (M7): the four choices, in the sheet's order. `other` reads as a moment.
    static let kindChoices: [(kind: MemoryKind, label: String)] = [
        (.event, "A moment"), (.fact, "Something about your life"), (.feeling, "A feeling"), (.goal, "Something you wanted"),
    ]

    var shownKind: MemoryKind { memory.kind == .other ? .event : memory.kind }

    func setKind(_ kind: MemoryKind) {
        guard kind != shownKind else { return }
        attempt("Could not change that") { try deps.actions.setKind(memory.id, kind) }
    }

    /// "Tell me when" from the sheet.
    func setStated(_ range: TimeRange) {
        attempt("Could not save that") { try deps.actions.setStatedRange(memory.id, range) }
    }

    var canSaveTitle: Bool {
        let t = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t != memory.title
    }

    func refresh() {
        guard !isGone else { return }
        do {
            let store = deps.extractionStore
            memory = try store.memories.fetch(memory.id) ?? memory
            people = try store.memories.people(of: memory.id)
            let linked = Set(people.map(\.id))
            choices = try store.people.people().filter { !$0.isOwner && !linked.contains($0.id) }
            parts = try store.memories.spans(of: memory.id).map { Part(span: $0, words: try store.sessions.words(in: $0.segmentID)) }
            when.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveTitle() {
        attempt("Could not change the title") { try deps.actions.renameMemory(memory.id, to: draftTitle) }
    }

    func add(_ person: Person) {
        attempt("Could not add \(person.displayName)") { try deps.actions.linkPerson(person.id, to: memory.id, roleText: nil) }
    }

    func addNew() {
        let name = newName
        attempt("Could not add that name") { try deps.actions.linkNewPerson(named: name, to: memory.id); newName = "" }
    }

    func remove(_ person: Person) {
        attempt("Could not remove \(person.displayName)") { try deps.actions.unlinkPerson(person.id, from: memory.id) }
    }

    private func attempt(_ message: String, _ work: () throws -> Void) {
        do { try work(); error = nil; refresh() } catch { self.error = "\(message): \(error.localizedDescription)" }
    }
}
