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
    private let deps: Dependencies

    init(memory: Memory, deps: Dependencies) {
        self.memory = memory
        self.deps = deps
        draftTitle = memory.title
        when = MemoryViewModel(memory: memory, deps: deps)
        refresh()
    }

    var canSaveTitle: Bool {
        let t = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t != memory.title
    }

    func refresh() {
        do {
            let store = deps.extractionStore
            memory = try store.memories.fetch(memory.id) ?? memory
            people = try store.memories.people(of: memory.id)
            let linked = Set(people.map(\.id))
            choices = try store.people.people().filter { !$0.isOwner && !linked.contains($0.id) }
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
