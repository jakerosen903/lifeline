import LifelineKit
import SwiftUI

/// A memory after Keep, while its follow-ups are still open: "Kept" with a checkmark, the title
/// on one line, one chip per follow-up in emitted order, and "Done". A person chip asks "Who's
/// this?" in a sheet; a choice closes it and checks the chip.
struct KeptCardView: View {
    let kept: KeptCard
    /// Chips answered with "Not any of these".
    var declined: Set<String> = []
    let peopleChoices: (String) -> [Person]
    let onFollowUp: (Card, EntityType?) -> Void
    let onResolve: (Card, MentionChoice) -> Void
    var onNotAny: (Card) -> Void = { _ in }
    let onDone: () -> Void
    /// Opens a checked entity or person chip's page; nil in the live session.
    var onOpenEntity: ((Card) -> Void)?
    /// Whether a checked chip has a page; one without (a hint, "Not a person") is not tappable.
    var hasPage: (Card) -> Bool = { _ in false }

    @State private var asking: Card?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kept", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.oliveText)
            Text(kept.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            FlowLayout(spacing: 6) {
                ForEach(kept.followUps) { followUp in
                    FollowUpChip(followUp: followUp, answered: kept.answered.contains(followUp.id), declined: declined.contains(followUp.id),
                                 onTap: { tap(followUp) },
                                 onRetype: { onFollowUp(followUp, $0) },
                                 onNotAny: { onNotAny(followUp) },
                                 onOpen: onOpenEntity.flatMap { open in hasPage(followUp) ? { open(followUp) } : nil })
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button("Done", action: onDone)
                    .buttonStyle(.bordered)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("card.keptDone")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.kept")
        .sheet(item: $asking) { card in
            if case .whoIsThis(_, let text) = card {
                ScrollView {
                    WhoIsThisCard(text: text, people: peopleChoices(text)) { choice in
                        asking = nil
                        onResolve(card, choice)
                    }
                    .padding(16)
                }
                .background(Theme.linen.ignoresSafeArea())
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func tap(_ followUp: Card) {
        if case .whoIsThis = followUp { asking = followUp } else { onFollowUp(followUp, nil) }
    }
}

extension Card {
    /// The card, or a kept card's follow-ups: what a screen checks so a name is not asked twice.
    var withFollowUps: [Card] {
        if case .kept(let kept) = self { kept.followUps } else { [self] }
    }
}
