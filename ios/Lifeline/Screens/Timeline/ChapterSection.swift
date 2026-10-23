import LifelineKit
import SwiftUI

/// A chapter heading with its span, the year axis, and the chapter's memory bands.
struct ChapterSection: View {
    let title: String
    let rangeText: String?
    let memories: [MemoryRow]
    let axis: ClosedRange<Int>?
    let actions: MemoryRowActions

    var body: some View {
        Section {
            if let axis { YearAxis(years: axis).listRowBackground(Color.clear).listRowSeparator(.hidden) }
            ForEach(memories) { row in
                MemoryRowView(row: row, axis: axis, actions: actions)
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
