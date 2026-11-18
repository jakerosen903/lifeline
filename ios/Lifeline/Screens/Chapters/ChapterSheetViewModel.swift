import Foundation
import LifelineKit

/// One chapter as its sheet shows it: the name, the years the person said, and the moments they
/// filed in it. Rename, say when, and remove go through `ChapterActions`. A removal hands its
/// receipt up through `onRemoved`, so the notice and its Undo outlive the sheet.
@MainActor
@Observable
final class ChapterSheetViewModel: Identifiable {
    struct Member: Identifiable, Equatable {
        let id: MemoryID
        let title: String
        let dateText: String
    }

    /// The sheet's title for a chapter with no name; the same words the life map uses.
    static let untitled = LifeMap.untitled
    /// The remove question for a chapter with no name. It quotes no name the person never gave (ruling R7).
    static let removeQuestionWithNoName = "Remove this chapter?"

    let id: ChapterID
    private(set) var name: String?
    private(set) var yearsText = ""
    private(set) var members: [Member] = []
    /// The chapter is gone (removed here, or elsewhere while the sheet was open): the sheet closes.
    private(set) var isGone = false
    /// The last rename asked for a name another chapter already has.
    private(set) var renameTaken = false
    private(set) var error: String?
    let birthDate: CivilDate?

    @ObservationIgnored private let store: ExtractionStore
    @ObservationIgnored private let onRemoved: (ChapterReceipt) -> Void
    private var actions: ChapterActions { ChapterActions(store: store) }

    var title: String { name ?? Self.untitled }
    /// "Remove “{name}”?", or "Remove this chapter?" for a chapter with no name.
    var removeQuestion: String { name.map { "Remove “\($0)”?" } ?? Self.removeQuestionWithNoName }

    init(chapter: ChapterID, store: ExtractionStore, onRemoved: @escaping (ChapterReceipt) -> Void) {
        id = chapter
        self.store = store
        self.onRemoved = onRemoved
        birthDate = try? store.profile.ownerBirthDate()
        reload()
    }

    /// Re-reads the chapter. Called after each action, so a chapter removed elsewhere is seen on the
    /// next action and the sheet closes; nothing else watches the store while the sheet is open.
    func reload() {
        do {
            guard let chapter = try store.chapters.chapter(id: id) else { isGone = true; return }
            name = chapter.name
            yearsText = chapter.statedYears?.displayText ?? "No dates yet"
            members = Self.members(try store.memories.moments(inChapter: id))
            error = nil
        } catch {
            self.error = "Could not load this chapter: \(error.localizedDescription)"
        }
    }

    /// True when the name changed. `.empty` cannot come from the sheet (Save is disabled), except for
    /// a name of punctuation only, which writes nothing and needs no message: the name stays as it was.
    @discardableResult
    func rename(to title: String) -> Bool {
        do {
            switch try actions.rename(id, to: title) {
            case .renamed: renameTaken = false; reload(); return true
            case .taken: renameTaken = true; return false
            case .empty: return false
            }
        } catch {
            self.error = "Could not rename this chapter: \(error.localizedDescription)"
            return false
        }
    }

    /// Cancel on the rename alert: the refused name is no longer the question, so its line goes.
    func cancelRename() { renameTaken = false }

    func sayWhen(_ range: TimeRange) {
        do { try actions.sayWhen(id, range); reload() }
        catch { self.error = "Could not save those years: \(error.localizedDescription)" }
    }

    /// No receipt means the chapter was already gone: the sheet closes with no notice.
    func remove() {
        do {
            if let receipt = try actions.remove(id) { onRemoved(receipt) }
            isGone = true
        } catch {
            self.error = "Could not remove this chapter: \(error.localizedDescription)"
        }
    }

    /// In time order by the likely start, else the earliest; undated last; ties by when they were told.
    static func members(_ moments: [Memory]) -> [Member] {
        moments.sorted { a, b in
            let ka = a.range.likelyStart ?? a.range.earliest, kb = b.range.likelyStart ?? b.range.earliest
            switch (ka, kb) {
            case (let x?, let y?): return x != y ? x < y : a.createdAt < b.createdAt
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.createdAt < b.createdAt
            }
        }.map { Member(id: $0.id, title: $0.title, dateText: $0.range.displayText) }
    }
}
