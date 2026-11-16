import LifelineKit
import SwiftUI

/// Memories with no year to show and no collection: "Somewhere in your story". A date with one end
/// only ("before 2004") sits here too, with its date text, until it has a year the spine can show.
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
                MemoryRowView(row: row, actions: actions, inline: true)
            }
            ForEach(stories) { story in
                StoryRowView(row: story, expanded: expanded.contains(story.id), onToggle: { onToggleStory(story.id) },
                             storyActions: storyActions)
                if expanded.contains(story.id) {
                    ForEach(story.members) { member in
                        MemoryRowView(row: member, actions: actions).padding(.leading, 16)
                    }
                }
            }
        } header: {
            HStack {
                Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink).textCase(nil)
                Spacer()
                Text("\(memories.count + stories.reduce(0) { $0 + $1.members.count }) undated").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timeline.shelf")
        }
    }
}
