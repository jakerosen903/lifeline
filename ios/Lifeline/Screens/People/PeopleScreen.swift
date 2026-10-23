import LifelineKit
import SwiftUI

/// People. The "Who's this?" queue first, then everyone with their aliases.
struct PeopleScreen: View {
    let viewModel: PeopleViewModel
    @State private var editing: PeopleViewModel.PersonRow?
    @State private var draftName = ""

    var body: some View {
        List {
            if !viewModel.queue.isEmpty {
                Section("Who's this?") {
                    CardStack(cards: viewModel.queue, handler: viewModel.cards,
                              onAccept: { _ in }, onChange: { _ in }, onDismiss: { viewModel.dismiss($0) },
                              onResolve: { viewModel.resolve($0, $1) }, onUndo: { viewModel.undo() })
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
                    Button {
                        draftName = row.person.displayName
                        editing = row
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.person.displayName)
                                    .font(.system(.headline, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                if let relation = row.relation {
                                    Text("· \(relation)").font(.subheadline).foregroundStyle(Theme.ochre)
                                }
                            }
                            let others = row.aliases.filter { $0 != row.relation }
                            if !others.isEmpty {
                                Text("also called " + others.map { "“\($0)”" }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.stone)
                            }
                        }
                        .padding(.vertical, 2)
                    }
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
        .alert("Fix the name", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), presenting: editing) { row in
            TextField("Name", text: $draftName)
                .autocorrectionDisabled()
                .accessibilityIdentifier("people.renameField")
            Button("Save") {
                viewModel.rename(row.person, to: draftName)
                editing = nil
            }
            .accessibilityIdentifier("people.renameSave")
            Button("Cancel", role: .cancel) { editing = nil }
        } message: { row in
            Text("“\(row.person.displayName)” stays as another spelling, so stories that use it still link.")
        }
    }
}
