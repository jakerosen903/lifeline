import LifelineKit
import SwiftUI

/// "Which one?": the nearest earlier memories, then "None of these". Used by a card's Same
/// story when more than one memory is plausible, and by the Change sheet.
struct SameAsPicker: View {
    let matches: [MemoryMatch]
    var title = "Which one?"
    let onChoose: (MemoryID?) -> Void
    @State private var search = ""

    private var shown: [MemoryMatch] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? matches : matches.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(shown) { match in
                    Button { onChoose(match.memoryID) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.title).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                            if let date = match.recordedAt {
                                Text("recorded " + date.formatted(.dateTime.month(.abbreviated).day().year())).font(.caption).foregroundStyle(Theme.stone)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("picker.match")
                }
                Button("None of these") { onChoose(nil) }
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("picker.none")
            }
            .searchable(text: $search, prompt: "Search your memories")
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
