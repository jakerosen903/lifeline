import LifelineKit
import SwiftUI

/// A memory found by search: it opens the memory's page in the search's own stack (decision 15).
/// Lines: the heading; the date, only when dated, in words so a guess reads as a guess (P5, decision 14);
/// the person's words around the match, when the heading does not already show them (decision 13).
/// One button for VoiceOver: label the heading, value the date and the words (decision 26).
struct SearchMemoryRow: View {
    let hit: SearchResults.MemoryHit
    let query: String
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        let snippet = SearchSnippet.line(for: hit, query: query)
        NavigationLink {
            MemoryScreen(viewModel: MemoryViewModel(memory: hit.memory, deps: deps), deps: deps, onChange: onChange)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.heading)
                    .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                if let date = hit.dateText {
                    Text(date).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ochreText)
                }
                if let snippet {
                    SnippetText(snippet: snippet)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hit.heading)
            .accessibilityValue([hit.dateText, snippet?.text].compactMap { $0 }.joined(separator: ". "))
        }
        .accessibilityIdentifier("search.result")
    }
}
