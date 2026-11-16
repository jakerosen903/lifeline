import LifelineKit
import SwiftUI

/// One follow-up on a kept card: a capsule button with the question ("Family?", "the shed: a
/// place?"), then a checkmark and the plain text once answered. A thing, place or idea offers the
/// other types and "Not any of these" on a long press, as "Not quite" did on the old entity card.
struct FollowUpChip: View {
    let followUp: Card
    let answered: Bool
    /// Answered with "Not any of these": struck through, no checkmark.
    var declined = false
    /// One tap on an open chip: a hint or entity is accepted as heard; a person asks "Who's this?".
    let onTap: () -> Void
    /// The type chosen from the context menu (entities only).
    var onRetype: (EntityType) -> Void = { _ in }
    var onNotAny: () -> Void = {}
    /// A checked entity or person chip opens that entity's page; nil in the live session.
    var onOpen: (() -> Void)?

    /// The other types an entity can be, in the order "Not quite" listed them.
    static let typeLabels: [(EntityType, String)] = [
        (.place, "It's a place"), (.person, "It's a person"), (.thing, "It's a thing"), (.idea, "Something I think"),
    ]

    private var heard: EntityType? {
        if case .entity(_, let mention) = followUp { mention.kind.entityType } else { nil }
    }

    /// The answered text without its checkmark.
    private var plain: String { String(FollowUpLabel.done(followUp).dropFirst(2)) }
    private var text: String { declined ? plain : answered ? FollowUpLabel.done(followUp) : FollowUpLabel.question(followUp) }
    /// VoiceOver reads the text without the checkmark, then "done".
    private var spoken: String {
        declined ? plain + ", not any of these" : answered ? plain + ", done" : FollowUpLabel.question(followUp)
    }

    var body: some View {
        Button {
            if !answered { onTap() } else { onOpen?() }
        } label: {
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
                .strikethrough(declined)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.linen))
                .foregroundStyle(answered ? Theme.secondaryText : Theme.oliveText)
        }
        .buttonStyle(.plain)
        .disabled(answered && (declined || onOpen == nil))
        .contextMenu {
            if let heard, !answered {
                ForEach(Self.typeLabels.filter { $0.0 != heard }, id: \.0) { type, label in
                    Button(label) { onRetype(type) }
                }
                Divider()
                Button("Not any of these", role: .destructive, action: onNotAny)
            }
        }
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("card.followUp")
    }
}
