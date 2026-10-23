import LifelineKit
import SwiftUI

/// "Which one?": the nearest earlier memories, then "None of these". Used by a card's Same
/// story when more than one memory is plausible, and by the Change sheet. With `preselected`
/// it picks several at once, the named ones checked by default (M5 groups).
struct SameAsPicker: View {
    let matches: [MemoryMatch]
    var title = "Which one?"
    var preselected: Set<MemoryID>? = nil
    let onChoose: ([MemoryID]) -> Void
    @State private var search = ""
    @State private var selected: Set<MemoryID> = []

    private var multi: Bool { preselected != nil }

    private var shown: [MemoryMatch] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? matches : matches.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(shown) { match in
                    Button {
                        if multi {
                            if selected.contains(match.memoryID) { selected.remove(match.memoryID) } else { selected.insert(match.memoryID) }
                        } else {
                            onChoose([match.memoryID])
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.title).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                                if let date = match.recordedAt {
                                    Text("recorded " + date.formatted(.dateTime.month(.abbreviated).day().year())).font(.caption).foregroundStyle(Theme.stone)
                                }
                            }
                            if multi {
                                Spacer()
                                Image(systemName: selected.contains(match.memoryID) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.olive)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(multi && selected.contains(match.memoryID) ? .isSelected : [])
                    .accessibilityIdentifier("picker.match")
                }
                Button("None of these") { onChoose([]) }
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("picker.none")
            }
            .searchable(text: $search, prompt: "Search your memories")
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if multi {
                    Button("Done") { onChoose(matches.map(\.memoryID).filter { selected.contains($0) }) }
                        .disabled(selected.isEmpty)
                        .accessibilityIdentifier("picker.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { selected = preselected ?? [] }
    }
}
