import LifelineKit
import SwiftUI

/// Cards in arrival order. The same component serves the live session and the detail screen.
struct CardStack: View {
    let cards: [Card]
    let handler: CardHandler
    let onAccept: (Card) -> Void
    let onDismiss: (Card) -> Void
    let onResolve: (Card, MentionChoice) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(cards) { card in
                switch card {
                case .memory(let candidate, let memory):
                    MemoryCard(memory: memory, confidence: candidate.confidence, onAdd: { onAccept(card) }, onDismiss: { onDismiss(card) })
                case .whoIsThis(_, let mention):
                    WhoIsThisCard(mention: mention, people: handler.peopleChoices()) { onResolve(card, $0) }
                        .onAppear { handler.shown(card) }
                }
            }
        }
        .animation(.default, value: cards.map(\.id))
    }
}
