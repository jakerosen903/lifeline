import Foundation
import LifelineKit

/// "Same as another person…" (PC-c): the people this one could be the same as, the check of the picked pair, and the
/// merge on "Merge". The person the owner picks stays; the other joins them (plan decision 2). Nothing is written
/// before `merge()`.
@MainActor
@Observable
final class PersonMergeViewModel {
    /// The picker's rows: every person but the one that goes and the owner, most recently linked first.
    private(set) var others: [Person] = []
    /// Set when a pair passed `check`; the confirm shows it.
    private(set) var preview: PersonMergePreview?
    /// The sentence for a pair that `check` or `merge` refused. The host shows it in its message slot.
    private(set) var refusal: String?
    let photoImages: PhotoImageCache

    private let actions: PersonMergeActions
    private let store: ExtractionStore
    /// Every person's key photo, read when the picker opens.
    private var covers: [EntityID: Photo] = [:]

    init(deps: Dependencies) {
        actions = deps.personMergeActions()
        store = deps.extractionStore
        photoImages = deps.photoImages
    }

    /// Reads the rows and the faces afresh, and forgets the last pair. A failed read leaves the picker empty.
    func openPicker(for person: PersonID) {
        preview = nil
        refusal = nil
        others = (try? actions.others(than: person)) ?? []
        covers = (try? store.photos.covers(type: .person)) ?? [:]
    }

    /// Runs the refusals before the owner is asked: sets `preview` for a pair that may merge, `refusal` otherwise.
    func ask(_ leaving: PersonID, into staying: PersonID) {
        preview = nil
        refusal = nil
        do {
            preview = try actions.check(leaving, into: staying)
        } catch {
            refusal = Self.sentence(for: error)
        }
    }

    /// Merges the previewed pair. Nil, with `refusal` set, when the write refused or failed (the refusals run again
    /// inside the write: a row can change between the confirm and the tap).
    func merge() -> PersonMergeReceipt? {
        guard let preview else { return nil }
        self.preview = nil
        do {
            return try actions.merge(preview.leaving.id, into: preview.staying.id)
        } catch {
            refusal = Self.sentence(for: error)
            return nil
        }
    }

    /// Hands the refusal to the host once, so a later dismiss does not show it again.
    func takeRefusal() -> String? {
        defer { refusal = nil }
        return refusal
    }

    func cover(of person: PersonID) -> Photo? { covers[EntityID(rawValue: person.rawValue)] }

    /// The plan's copy. The picker never lists the person themself or the owner, so those refusals mean the rows
    /// changed under the sheet: they read as "not here any more". Any other failure is the page's usual save line.
    static func sentence(for error: Swift.Error) -> String {
        switch error as? PersonMergeActions.Error {
        case .twoContacts: "They are linked to two different contacts."
        case .notFound, .samePerson, .owner, .stale: PersonChipLine.refusal(.notFound)
        case nil: "Could not save that: \(error.localizedDescription)"
        }
    }
}
