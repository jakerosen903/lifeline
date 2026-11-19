import Foundation
import LifelineKit

/// The rows of one kind of entity: People, Places and Things each have a tab; ideas list on You.
/// A free-text tag narrows any of them. The owner is never a row: their page is "About you" on You.
@MainActor
@Observable
final class EntitiesViewModel {
    let type: EntityType
    var tagFilter: String? { didSet { refresh() } }
    private(set) var rows: [EntitySummary] = []
    /// Each entity's cover photo, for People only: its tiles show them. Places and Things read none.
    private(set) var covers: [EntityID: Photo] = [:]
    private(set) var allTags: [String] = []
    /// The owner's own page: "About you" (M7), on the You tab.
    private(set) var aboutYou: Entity?
    private(set) var error: String?
    /// The first read has run. Until then a screen shows no "Nothing yet" text.
    private(set) var isLoaded = false
    let deps: Dependencies
    /// People only: the check and the merge of a face dropped onto another (PC-c). Nil for places and things.
    let merge: PersonMergeViewModel?
    /// People only: the grid's message slot, "Merged into {name}." with Undo, or a refusal. Nil for places and things.
    let notice: PersonMoveUndo?

    init(deps: Dependencies, type: EntityType) {
        self.deps = deps
        self.type = type
        merge = type == .person ? PersonMergeViewModel(deps: deps) : nil
        notice = type == .person ? PersonMoveUndo(actions: deps.personLinkActions()) : nil
    }

    func refresh() {
        defer { isLoaded = true }
        do {
            let store = deps.extractionStore
            allTags = try store.tags.all()
            let tagged = try tagFilter.map { try store.tags.elements(.entity, tagged: $0) }
            let owner = try store.profile.owner()?.entityID
            aboutYou = try owner.flatMap { try store.entities.entity(id: $0) }
            rows = try store.entities.summaries(type: type)
                .filter { $0.id != owner && (tagged?.contains($0.id.rawValue) ?? true) }
            // One statement, whatever the number of people.
            covers = type == .person ? try store.photos.covers(type: .person) : [:]
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Merge (People only)

    /// `leaving` was dropped onto `staying`, who stays (plan decision 2). Returns true when the pair may merge and the
    /// confirm should open; a refused pair says why in the slot. Nothing is written here.
    func askMerge(_ leaving: EntityID, into staying: EntityID) -> Bool {
        guard let merge else { return false }
        notice?.clearMessage()
        merge.openConfirm(PersonID(rawValue: leaving.rawValue), into: PersonID(rawValue: staying.rawValue))
        if merge.preview != nil { return true }
        mergeRefused()
        return false
    }

    /// "Merge" on the confirm: the notice offers Undo, and the grid reads again without the person that left.
    func merged(_ receipt: PersonMergeReceipt) {
        let actions = deps.personMergeActions()
        notice?.offer("Merged into \(receipt.stayingName).") { try actions.undo(receipt) }
        refresh()
    }

    /// A refusal from the confirm (the write refused), in the grid's slot.
    func mergeRefused() {
        if let sentence = merge?.takeRefusal() { notice?.say(sentence) }
    }

    /// Undo on the notice: the person that left is back on the grid. A refused Undo says why in the slot.
    func undoMerge() {
        if notice?.undo() == true { refresh() }
    }
}
