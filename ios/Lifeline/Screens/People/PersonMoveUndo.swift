import Foundation
import LifelineKit
import SwiftUI

/// The one message slot for people: "Changed to {name}." after the "Who is this?" sheet moved a name, or
/// "Merged into {name}." after a merge, each with Undo for the usual 6-second window. Each host shows it in the slot
/// it already has: the card stack's notices, or the page's pinned slot. A refused Undo leaves its reason in the same
/// place, with no Undo.
@MainActor
@Observable
final class PersonMoveUndo {
    private(set) var text: String?
    /// True while the offer can still be taken back.
    var canUndo: Bool { pendingUndo != nil }
    /// What Undo runs. Nil when the slot shows a message with no Undo, or nothing.
    private var pendingUndo: (@MainActor () throws -> Void)?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let actions: PersonLinkActions

    init(actions: PersonLinkActions) { self.actions = actions }

    /// What the sheet returned. Only a move offers Undo; a settle or a stored choice has nothing to take back.
    func note(_ outcome: WhoIsThisViewModel.Outcome) {
        guard case .moved(let receipt) = outcome else { return }
        offer(PersonChipLine.movedNotice(newName: receipt.newName)) { [actions] in try actions.undo(receipt) }
    }

    /// A notice with Undo. It replaces what shows, an earlier offer included: only the latest act can be taken back.
    func offer(_ text: String, undo: @escaping @MainActor () throws -> Void) {
        pendingUndo = undo
        show(text)
    }

    /// Another message for the same slot, with no Undo (a person's contact row, PB50). It replaces what shows, a move's
    /// offer included, and clears after the usual window.
    func say(_ sentence: String) {
        pendingUndo = nil
        show(sentence)
    }

    /// The next action began: a message with no Undo goes. A move's offer stays until its window ends.
    func clearMessage() {
        guard pendingUndo == nil, text != nil else { return }
        timer?.cancel()
        text = nil
    }

    /// Returns true when the offer was taken back. A refusal says why in the slot and ends the offer.
    @discardableResult func undo() -> Bool {
        guard let pendingUndo else { return false }
        self.pendingUndo = nil
        do {
            try pendingUndo()
            timer?.cancel()
            text = nil
            return true
        } catch {
            show(PersonChipLine.undoRefused(error))
        }
        return false
    }

    private func show(_ sentence: String) {
        text = sentence
        AccessibilityNotification.Announcement(sentence).post()
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: CardHandler.undoWindow)
            guard !Task.isCancelled, let self else { return }
            self.pendingUndo = nil
            self.text = nil
        }
    }
}

/// The page's pinned slot for the notice: above the record bar, wherever the page is scrolled.
struct PersonMoveNoticeSlot: View {
    let notice: PersonMoveUndo
    let onUndo: () -> Void

    var body: some View {
        if let text = notice.text {
            NoticeSlot(text: text, identifier: "person.notice") {
                if notice.canUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Theme.oliveOnFill)
                        .accessibilityIdentifier("notice.undo")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}
