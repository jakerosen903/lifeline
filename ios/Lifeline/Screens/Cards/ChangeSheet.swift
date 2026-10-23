import LifelineKit
import SwiftUI

/// Change… : one tap from any card. The title, who was there, when it was; two rows that wait.
struct ChangeSheet: View {
    @Bindable var viewModel: ChangeViewModel
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showWhen = false

    var body: some View {
        NavigationStack {
            Form {
                Section("The title") {
                    TextField("In your words", text: $viewModel.draftTitle, axis: .vertical)
                        .font(.system(.body, design: .serif))
                        .accessibilityIdentifier("change.title")
                        .onSubmit { if viewModel.canSaveTitle { viewModel.saveTitle() } }
                    Button("Save the title") { viewModel.saveTitle() }
                        .buttonStyle(.borderless)
                        .disabled(!viewModel.canSaveTitle)
                        .accessibilityIdentifier("change.saveTitle")
                    Text("“\(viewModel.memory.summaryQuote)”")
                        .font(.footnote).foregroundStyle(Theme.stone)
                }

                Section("Who was there") {
                    ForEach(viewModel.people) { person in
                        HStack {
                            Text(person.displayName)
                            Spacer()
                            Button("Remove") { viewModel.remove(person) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Theme.stone)
                                .accessibilityIdentifier("change.removePerson")
                        }
                    }
                    if !viewModel.choices.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.choices) { person in
                                Button(person.displayName) { viewModel.add(person) }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.olive)
                                    .accessibilityIdentifier("change.addPerson")
                            }
                        }
                    }
                    HStack {
                        TextField("Someone else", text: $viewModel.newName)
                            .accessibilityIdentifier("change.personName")
                            .onSubmit { viewModel.addNew() }
                        Button("Add") { viewModel.addNew() }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("change.addName")
                    }
                }

                Section("When it was") {
                    Button {
                        showWhen.toggle()
                    } label: {
                        HStack {
                            Text(viewModel.when.rangeText).foregroundStyle(viewModel.when.isGuess ? Theme.ochre : Theme.ink)
                            Spacer()
                            Image(systemName: showWhen ? "chevron.up" : "chevron.down").foregroundStyle(Theme.stone)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("change.when")
                    if showWhen {
                        RefineCard(title: viewModel.memory.title, bestGuess: viewModel.when.rangeText, question: viewModel.when.question,
                                   onChoose: { viewModel.when.answer($0); viewModel.refresh(); showWhen = false },
                                   onKeep: { showWhen = false })
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    laterRow("Which part of the recording")
                    laterRow("Just tell me")
                } footer: {
                    Text("These come later, with the interviewer.")
                }

                if let error = viewModel.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("change.error")
                }
            }
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle("Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { onDone(); dismiss() }.accessibilityIdentifier("change.done")
            }
        }
        .presentationDetents([.large])
        .onDisappear { onDone() }
    }

    private func laterRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("later").font(.caption).foregroundStyle(Theme.stone)
        }
        .foregroundStyle(Theme.stone)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("change.later")
    }
}
