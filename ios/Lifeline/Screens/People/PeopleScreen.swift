import LifelineKit
import SwiftUI

/// People. The "Who's this?" queue first, then everyone with their aliases.
struct PeopleScreen: View {
    let viewModel: PeopleViewModel

    var body: some View {
        List {
            if !viewModel.queue.isEmpty {
                Section("Who's this?") {
                    CardStack(cards: viewModel.queue, handler: viewModel.cards,
                              onAccept: { _ in }, onDismiss: { viewModel.dismiss($0) },
                              onResolve: { viewModel.resolve($0, $1) })
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            Section("In your story") {
                if viewModel.people.isEmpty {
                    Text("No one yet. People appear as you tell stories.")
                        .foregroundStyle(Theme.stone)
                }
                ForEach(viewModel.people) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.person.displayName)
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if !row.aliases.isEmpty {
                            Text("also called " + row.aliases.map { "“\($0)”" }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Theme.stone)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("people.row")
                }
            }
            if let error = viewModel.error ?? viewModel.cards.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
        .navigationTitle("People")
        .onAppear { viewModel.refresh() }
    }
}
