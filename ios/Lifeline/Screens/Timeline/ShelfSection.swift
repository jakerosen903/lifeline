import LifelineKit
import SwiftUI

/// Memories with neither a date nor a collection: "Somewhere in your story".
struct ShelfSection: View {
    let title: String
    let memories: [MemoryRow]
    let actions: MemoryRowActions
    /// Stories whose members are all undated sit here as one row each (M5).
    var stories: [StoryRow] = []
    var expanded: Set<StoryID> = []
    var onToggleStory: (StoryID) -> Void = { _ in }
    var storyActions = StoryRowActions(rename: { _ in }, split: { _ in })

    var body: some View {
        Section {
            ForEach(memories) { row in
                MemoryRowView(row: row, axis: nil, actions: actions, inline: true)
            }
            ForEach(stories) { story in
                StoryRowView(row: story, axis: nil, expanded: expanded.contains(story.id), onToggle: { onToggleStory(story.id) },
                             actions: actions, storyActions: storyActions)
            }
        } header: {
            HStack {
                Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink).textCase(nil)
                Spacer()
                Text("\(memories.count + stories.reduce(0) { $0 + $1.members.count }) undated").font(.caption).foregroundStyle(Theme.stone)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timeline.shelf")
        }
    }
}
