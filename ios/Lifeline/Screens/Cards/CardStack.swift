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

    var body: some View {
        VStack(spacing: 12) {
            ForEach(cards) { card in
                switch card {
                case .memory(let candidate, let memory):
                    MemoryCard(memory: memory, confidence: candidate.confidence,
                               onKeep: { onAccept(card) }, onChange: { onChange(card) }, onDismiss: { onDismiss(card) })
                case .whoIsThis(_, let text):
                    WhoIsThisCard(text: text, people: handler.peopleChoices(for: text)) { onResolve(card, $0) }
                        .onAppear { handler.shown(card) }
                case .hint(_, let hint):
                    HintCard(hint: hint, onAccept: { onAccept(card) }, onDismiss: { onDismiss(card) })
                }
            }
            if handler.undoCard != nil {
                DismissedNotice(onUndo: onUndo)
            }
        }
        .animation(.default, value: cards.map(\.id))
        .animation(.default, value: handler.undoCard?.id)
    }
}
