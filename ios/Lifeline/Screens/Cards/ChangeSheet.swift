import LifelineKit
import SwiftUI

/// Change… : one tap from any card. The title, who was there, when it was; two rows that wait.
struct ChangeSheet: View {
    @State private var viewModel: ChangeViewModel
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// The model is created once per presentation: a parent re-render must not reset a merge
    /// in progress or a half-typed title.
    init(memory: Memory, deps: Dependencies, includeHidden: Bool = false, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: ChangeViewModel(memory: memory, deps: deps, includeHidden: includeHidden))
        self.onDone = onDone
    }
    @State private var showWhen = false
    @State private var tellingWhen = false
    @State private var pickingSameAs = false
    @State private var trimming = false

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

                if viewModel.memory.isMoment {
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
                    Button("Tell me when", systemImage: "calendar") { tellingWhen = true }
                        .buttonStyle(.borderless)
                        .tint(Theme.olive)
                        .accessibilityIdentifier("change.tellMeWhen")
                }
                }

                Section {
                    if let merged = viewModel.mergedInto {
                        HStack {
                            Text("Merged into “\(merged)”").foregroundStyle(Theme.ink)
                                .accessibilityIdentifier("change.merged")
                            Spacer()
                            Button("Undo") { viewModel.undoMerge() }
                                .buttonStyle(.bordered).tint(Theme.olive)
                                .accessibilityIdentifier("change.undoMerge")
                        }
                    } else {
                        Button("Same as another memory…", systemImage: "arrow.triangle.merge") { pickingSameAs = true }
                            .buttonStyle(.borderless)
                            .tint(Theme.olive)
                            .accessibilityIdentifier("change.sameAs")
                    }
                } header: {
                    Text("Same story")
                } footer: {
                    Text("This becomes a later telling of the one you pick. Its words and audio stay.")
                }

                Section {
                    if let trimmed = viewModel.trimmedNotice {
                        HStack {
                            Text(trimmed).foregroundStyle(Theme.ink).accessibilityIdentifier("change.trimmed")
                            Spacer()
                            Button("Undo") { viewModel.undoTrim() }
                                .buttonStyle(.bordered).tint(Theme.olive)
                                .accessibilityIdentifier("change.undoTrim")
                        }
                    }
                    Button("Which part of the recording", systemImage: "waveform.path") { trimming = true }
                        .buttonStyle(.borderless)
                        .tint(Theme.olive)
                        .disabled(viewModel.parts.isEmpty)
                        .accessibilityIdentifier("change.whichPart")
                    laterRow("Just tell me")
                } footer: {
                    Text("Move where this telling starts and ends; the words and audio stay. \"Just tell me\" comes later, with the interviewer.")
                }

                // At the bottom, one row: the sheet's other rows keep their places (M7).
                Section("What is this?") {
                    Menu {
                        ForEach(ChangeViewModel.kindChoices, id: \.kind) { choice in
                            Button {
                                viewModel.setKind(choice.kind)
                            } label: {
                                if viewModel.shownKind == choice.kind { Label(choice.label, systemImage: "checkmark") } else { Text(choice.label) }
                            }
                            .accessibilityIdentifier("change.kind.\(choice.kind.rawValue)")
                        }
                    } label: {
                        HStack {
                            Text(ChangeViewModel.kindChoices.first { $0.kind == viewModel.shownKind }?.label ?? "A moment").foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.stone)
                        }
                    }
                    .accessibilityIdentifier("change.kind")
                    if !viewModel.memory.isMoment {
                        Menu {
                            Button("Nothing in particular (About)") { viewModel.moveDetail(to: nil) }
                            ForEach(viewModel.aboutChoices, id: \.entity.id) { choice in
                                Button(choice.label) { viewModel.moveDetail(to: choice.entity.id) }
                            }
                        } label: {
                            HStack {
                                Text("About whom or what?").foregroundStyle(Theme.stone)
                                Spacer()
                                Text(viewModel.aboutLabel).foregroundStyle(Theme.ink)
                            }
                        }
                        .accessibilityIdentifier("change.about")
                    }
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
        .sheet(isPresented: $tellingWhen) {
            TellMeWhenSheet(title: viewModel.memory.title, birthDate: viewModel.when.birthDate) { viewModel.setStated($0) }
        }
        .sheet(isPresented: $trimming) {
            TrimSheet(parts: viewModel.parts, deps: viewModel.deps, title: viewModel.memory.title) { order, start, end in
                viewModel.trim(order: order, startWord: start, endWord: end)
            }
        }
        .sheet(isPresented: $pickingSameAs) {
            SameAsPicker(matches: viewModel.pickerMatches(), title: "Same as which memory?") { chosen in
                pickingSameAs = false
                if let target = chosen.first { viewModel.merge(into: target) }
            }
        }
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
