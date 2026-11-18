import Foundation
import LifelineKit

/// Every chapter on one year axis (`LifeMap`), read fresh from the store on each `reload()`.
@MainActor
@Observable
final class LifeMapViewModel: Identifiable {
    private(set) var map: LifeMap?
    /// Chapters whose stated years have no end: their bar has an open right edge, so the shape
    /// says "still going" as well as the colour.
    private(set) var openEnded: Set<ChapterID> = []
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
            // The same rule `LifeMap` places by: stated years with neither a latest nor a likely end.
            openEnded = Set(chapters.filter { chapter in
                guard let years = chapter.statedYears else { return false }
                return years.latest == nil && years.likelyEnd == nil
            }.map(\.id))
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
