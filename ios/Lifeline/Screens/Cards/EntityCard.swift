import LifelineKit
import SwiftUI

/// "Sounds like a thing you had" / "Sounds like a place" / "Sounds like something you think"
/// (M7). Keep makes it what the card heard; Not quite offers the other types, so a wrong type
/// is one tap to fix, never a dismiss; "Not any of these" lets it go.
struct EntityCard: View {
    let mention: MentionOut
    let onKeep: (EntityType?) -> Void
    let onNotAny: () -> Void

    private var heard: EntityType { mention.kind.entityType }

    private static let otherLabels: [(EntityType, String)] = [
        (.place, "It's a place"), (.person, "It's a person"), (.thing, "It's a thing"), (.idea, "Something I think"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heard.cardHeading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.olive)
            Text("“\(mention.kind == .idea ? (mention.title ?? mention.text) : mention.text)”")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 12) {
                Button("Keep") { onKeep(nil) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("card.entityKeep")
                Menu {
                    ForEach(Self.otherLabels.filter { $0.0 != heard }, id: \.0) { type, label in
                        Button(label) { onKeep(type) }
                    }
                    Divider()
                    Button("Not any of these", role: .destructive, action: onNotAny)
                        .accessibilityIdentifier("card.entityNotAny")
                } label: {
                    Text("Not quite").foregroundStyle(Theme.stone)
                }
                .accessibilityIdentifier("card.entityNotQuite")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.entity")
    }
}
