import LifelineKit
import SwiftUI

/// A chapter heading with its span, the year axis, and the chapter's memory bands.
struct ChapterSection: View {
    let title: String
    let rangeText: String?
    let memories: [MemoryRow]
    let axis: ClosedRange<Int>?
    let onOpen: (MemoryRow) -> Void
    let onNewChapter: (MemoryRow) -> Void
    let onAddToCollection: (MemoryRow) -> Void

    var body: some View {
        Section {
            if let axis { YearAxis(years: axis).listRowBackground(Color.clear).listRowSeparator(.hidden) }
            ForEach(memories) { row in
                Button { onOpen(row) } label: { MemoryBand(row: row, axis: axis) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timeline.memory")
                    .contextMenu {
                        Button("New chapter from here", systemImage: "book") { onNewChapter(row) }
                        Button("Add to a collection…", systemImage: "square.stack") { onAddToCollection(row) }
                    }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                if let rangeText { Text(rangeText).font(.caption).foregroundStyle(Theme.ochre) }
                Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink).textCase(nil)
            }
            .accessibilityIdentifier("timeline.chapter")
        }
    }
}
