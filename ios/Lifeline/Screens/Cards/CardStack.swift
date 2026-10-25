import LifelineKit
import SwiftUI

/// Cards in arrival order, then the undo notice while a dismiss can still be taken back. The
/// same component serves the live session, the session detail and the timeline. Pair cards
/// (M5) sit after the memory and hint cards and before the questions.
struct CardStack: View {
    let cards: [Card]
    let handler: CardHandler
    let onAccept: (Card) -> Void
    let onChange: (Card) -> Void
    let onDismiss: (Card) -> Void
    let onResolve: (Card, MentionChoice) -> Void
    let onUndo: () -> Void
    /// "Same story" chose one memory, or several for a group (M5), for this card. Absent where
    /// cards cannot be memories.
    var onSameStory: (Card, [MemoryID]) -> Void = { _, _ in }
    /// Undo under "Added to X." Its own action: it must never undo a dismiss made moments before.
    var onUndoMerge: () -> Void = {}
    /// "Are these the same?" cards and their answers (M5): true means Same story / One story.
    var pairs: [PairRow] = []
    var onPair: (PairRow, Bool) -> Void = { _, _ in }
    var onUndoPair: () -> Void = {}
    /// Keep on an entity card, as what it heard (nil) or the type chosen under Not quite (M7).
    var onKeepEntity: (Card, EntityType?) -> Void = { _, _ in }

    @State private var picking: Card?

    private var questions: [Card] { cards.filter { if case .whoIsThis = $0 { true } else { false } } }
    private var others: [Card] { cards.filter { if case .whoIsThis = $0 { false } else { true } } }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(others) { card in cardView(card) }
            ForEach(pairs) { row in
                PairCard(row: row, isPlaying: { handler.isPairPlaying($0) }, onPlay: { handler.togglePairPlayback($0) },
                         onSame: { onPair(row, true) }, onSeparate: { onPair(row, false) })
            }
            ForEach(questions) { card in cardView(card) }
            if handler.undoCard != nil {
                UndoNotice(onUndo: onUndo)
            }
            if let merged = handler.mergedNotice {
                UndoNotice(text: merged, identifier: "card.mergedNotice", undoIdentifier: "card.undoMerge", onUndo: onUndoMerge)
            }
            if let pair = handler.pairNotice {
                UndoNotice(text: pair, identifier: "pair.notice", undoIdentifier: "pair.undo", onUndo: onUndoPair)
            }
        }
        .animation(.default, value: cards.map(\.id))
        .animation(.default, value: pairs.map(\.id))
        .animation(.default, value: handler.undoCard?.id)
        .animation(.default, value: handler.mergedNotice)
        .animation(.default, value: handler.pairNotice)
        .sheet(item: $picking) { card in
            let named = handler.suggestions(for: card).filter { $0.source == .extractor }.map(\.memoryID)
            SameAsPicker(matches: handler.pickerMatches(for: card), preselected: named.count > 1 ? Set(named) : nil) { chosen in
                picking = nil
                if !chosen.isEmpty { onSameStory(card, chosen) }
            }
        }
    }

    @ViewBuilder
    private func cardView(_ card: Card) -> some View {
        switch card {
        case .memory(let candidate, let memory):
            MemoryCard(memory: memory, confidence: candidate.confidence, matches: handler.suggestions(for: card),
                       storyLine: handler.storyLine(for: card, among: cards),
                       onKeep: { onAccept(card) }, onChange: { onChange(card) }, onDismiss: { onDismiss(card) },
                       onSameStory: { sameStory(card) }, onNotPartOfIt: { handler.notPartOfStory(card) })
        case .whoIsThis(_, let text):
            WhoIsThisCard(text: text, people: handler.peopleChoices(for: text)) { onResolve(card, $0) }
                .onAppear { handler.shown(card) }
        case .hint(_, let hint):
            HintCard(hint: hint, onAccept: { onAccept(card) }, onDismiss: { onDismiss(card) })
        case .entity(_, let mention):
            EntityCard(mention: mention, onKeep: { type in onKeepEntity(card, type) }, onNotAny: { onDismiss(card) })
        }
    }

    /// One strong answer merges at once; more than one plausible answer asks "Which one?"; a
    /// card that names several memories asks with those checked.
    private func sameStory(_ card: Card) {
        let named = handler.suggestions(for: card).filter { $0.source == .extractor }
        if named.count > 1 { picking = card; return }
        let matches = handler.pickerMatches(for: card)
        let plausible = matches.filter { handler.isStrong($0) }
        if plausible.count <= 1, let suggested = handler.suggestion(for: card) {
            onSameStory(card, [suggested.memoryID])
        } else {
            picking = card
        }
    }
}
