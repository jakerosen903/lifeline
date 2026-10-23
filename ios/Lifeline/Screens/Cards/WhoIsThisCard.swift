import LifelineKit
import SwiftUI

/// "Who's this?": the name as said, up to three known people, someone new, or not a person.
struct WhoIsThisCard: View {
    let mention: MentionOut
    let people: [Person]
    let onChoose: (MentionChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who's this?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ochre)
            Text("“\(mention.text)”")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            ForEach(people) { person in
                Button { onChoose(.existing(person.id)) } label: {
                    Label(person.displayName, systemImage: "person")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Theme.olive)
                .accessibilityIdentifier("card.person")
            }
            Button { onChoose(.new(displayName: mention.text)) } label: {
                Label("Someone new", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.olive)
            .accessibilityIdentifier("card.newPerson")
            Button("Not a person") { onChoose(.notAPerson) }
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier("card.notAPerson")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.whoIsThis")
    }
}
