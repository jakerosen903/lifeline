import LifelineKit
import SwiftUI

/// "Add to a chapter…": the chapters the person has named, or a new name in their own words.
struct AddToChapterSheet: View {
    let chapters: [Chapter]
    /// The moment's chapter now. It shows a checkmark and cannot be picked again; nil for none, or for one with no name.
    let currentChapter: ChapterID?
    let onPick: (ChapterID) -> Void
    let onAddNamed: (String) -> Void
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    private var canAdd: Bool { !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            // A List, so at the largest text size the chapters scroll and the field and Add stay in the same scroll.
            List {
                if chapters.isEmpty {
                    Section {
                        Text("A chapter is a name you gave to a stretch of your life.").foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    Section {
                        ForEach(chapters) { chapter in
                            Button { onPick(chapter.id); dismiss() } label: {
                                HStack {
                                    Text(chapter.name ?? "")
                                    Spacer()
                                    if chapter.id == currentChapter { Image(systemName: "checkmark") }
                                }
                            }
                            .foregroundStyle(Theme.ink)
                            .disabled(chapter.id == currentChapter)
                            .accessibilityIdentifier("chapter.pick")
                        }
                    }
                }
                Section {
                    TextField("A new chapter, in your own words", text: $newName)
                        .accessibilityIdentifier("chapter.newName")
                    Button("Add") { onAddNamed(newName); dismiss() }
                        .disabled(!canAdd)
                        .accessibilityIdentifier("chapter.add")
                }
            }
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle("Add to a chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("chapter.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
