import Foundation
import LifelineKit

/// Every chapter on one year axis (`LifeMap`), read fresh from the store on each `reload()`.
@MainActor
@Observable
final class LifeMapViewModel: Identifiable {
    private(set) var map: LifeMap?
    private(set) var error: String?
    let birthDate: CivilDate?

    @ObservationIgnored private let store: ExtractionStore
    @ObservationIgnored private let onRemoved: (ChapterReceipt) -> Void

    init(store: ExtractionStore, onRemoved: @escaping (ChapterReceipt) -> Void) {
        self.store = store
        self.onRemoved = onRemoved
        birthDate = try? store.profile.ownerBirthDate()
        reload()
    }

    func reload() {
        do {
            let chapters = try store.chapters.chapters()
            var counts: [ChapterID: Int] = [:]
            for chapter in chapters { counts[chapter.id] = try store.memories.moments(inChapter: chapter.id).count }
            map = LifeMap(chapters: chapters, momentCounts: counts, birthYear: birthDate?.year, currentYear: CivilDate.today().year)
            error = nil
        } catch {
            self.error = "Could not load your chapters: \(error.localizedDescription)"
        }
    }

    func chapterSheet(for id: ChapterID) -> ChapterSheetViewModel {
        ChapterSheetViewModel(chapter: id, store: store, onRemoved: onRemoved)
    }

    /// "Say when" on a chapter not placed in time yet.
    func sayWhen(_ id: ChapterID, _ range: TimeRange) {
        do { try ChapterActions(store: store).sayWhen(id, range); reload() }
        catch { self.error = "Could not save those years: \(error.localizedDescription)" }
    }
}
