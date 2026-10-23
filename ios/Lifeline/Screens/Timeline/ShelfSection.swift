import LifelineKit
import SwiftUI

/// Memories with neither a date nor a collection: "Somewhere in your story".
struct ShelfSection: View {
    let title: String
    let memories: [MemoryRow]
    let onOpen: (MemoryRow) -> Void
    let onNewChapter: (MemoryRow) -> Void
    let onAddToCollection: (MemoryRow) -> Void

    var body: some View {
        Section {
            ForEach(memories) { row in
                Button { onOpen(row) } label: { MemoryBand(row: row, axis: nil) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timeline.memory")
                    .contextMenu {
                        Button("New chapter from here", systemImage: "book") { onNewChapter(row) }
                        Button("Add to a collection…", systemImage: "square.stack") { onAddToCollection(row) }
                    }
            }
        } header: {
            HStack {
                Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink).textCase(nil)
                Spacer()
                Text("\(memories.count) undated").font(.caption).foregroundStyle(Theme.stone)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timeline.shelf")
        }
    }
}
