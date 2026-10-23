import LifelineKit
import SwiftUI

/// "Who's this?": the name as said, the three closest known people, everyone else behind
/// "Someone else", someone new, or not a person.
struct WhoIsThisCard: View {
    let text: String
    let people: [Person]
    let onChoose: (MentionChoice) -> Void

    private static let shown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who's this?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ochre)
            Text("“\(text)”")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            ForEach(people.prefix(Self.shown)) { person in
                Button { onChoose(.existing(person.id)) } label: {
                    Label(person.displayName, systemImage: "person")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Theme.olive)
                .accessibilityIdentifier("card.person")
            }
            if people.count > Self.shown {
                Menu {
                    ForEach(people.dropFirst(Self.shown)) { person in
                        Button(person.displayName) { onChoose(.existing(person.id)) }
                    }
                } label: {
                    Label("Someone else", systemImage: "person.3")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Theme.stone)
                .accessibilityIdentifier("card.someoneElse")
            }
            Button { onChoose(.new(displayName: text)) } label: {
                Label("Someone new", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.olive)
            .accessibilityIdentifier("card.newPerson")
            Button("Not a person") { onChoose(.notAPerson) }
                .buttonStyle(.borderless)
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
