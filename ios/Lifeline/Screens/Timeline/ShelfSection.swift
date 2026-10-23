import LifelineKit
import SwiftUI

/// Memories with neither a date nor a collection: "Somewhere in your story".
struct ShelfSection: View {
    let title: String
    let memories: [MemoryRow]
    let actions: MemoryRowActions

    var body: some View {
        Section {
            ForEach(memories) { row in
                MemoryRowView(row: row, axis: nil, actions: actions, inline: true)
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
