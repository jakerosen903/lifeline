import LifelineKit
import SwiftUI

/// Cards in arrival order, then the undo notice while a dismiss can still be taken back. The
/// same component serves the live session, the session detail and the timeline.
struct CardStack: View {
    let cards: [Card]
    let handler: CardHandler
    let onAccept: (Card) -> Void
    let onChange: (Card) -> Void
    let onDismiss: (Card) -> Void
    let onResolve: (Card, MentionChoice) -> Void
    let onUndo: () -> Void
    /// "Same story" chose a memory for this card (M4.1). Absent where cards cannot be memories.
    var onSameStory: (Card, MemoryID) -> Void = { _, _ in }
    /// Undo under "Added to X." Its own action: it must never undo a dismiss made moments before.
    var onUndoMerge: () -> Void = {}

    @State private var picking: Card?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(cards) { card in
                switch card {
                case .memory(let candidate, let memory):
                    MemoryCard(memory: memory, confidence: candidate.confidence, match: handler.suggestion(for: card),
                               onKeep: { onAccept(card) }, onChange: { onChange(card) }, onDismiss: { onDismiss(card) },
                               onSameStory: { sameStory(card) })
                case .whoIsThis(_, let text):
                    WhoIsThisCard(text: text, people: handler.peopleChoices(for: text)) { onResolve(card, $0) }
                        .onAppear { handler.shown(card) }
                case .hint(_, let hint):
                    HintCard(hint: hint, onAccept: { onAccept(card) }, onDismiss: { onDismiss(card) })
                }
            }
            if handler.undoCard != nil {
                UndoNotice(onUndo: onUndo)
            }
            if let merged = handler.mergedNotice {
                UndoNotice(text: merged, identifier: "card.mergedNotice", undoIdentifier: "card.undoMerge", onUndo: onUndoMerge)
            }
        }
        .animation(.default, value: cards.map(\.id))
        .animation(.default, value: handler.undoCard?.id)
        .animation(.default, value: handler.mergedNotice)
        .sheet(item: $picking) { card in
            SameAsPicker(matches: handler.pickerMatches(for: card)) { chosen in
                picking = nil
                if let chosen { onSameStory(card, chosen) }
            }
        }
    }

    /// One strong answer merges at once; more than one plausible answer asks "Which one?".
    private func sameStory(_ card: Card) {
        let matches = handler.pickerMatches(for: card)
        let plausible = matches.filter { handler.isStrong($0) }
        if plausible.count <= 1, let suggested = handler.suggestion(for: card) {
            onSameStory(card, suggested.memoryID)
        } else {
            picking = card
        }
    }
}
