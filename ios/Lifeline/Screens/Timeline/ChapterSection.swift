import LifelineKit
import SwiftUI

/// A chapter heading with its span, the year axis, and the chapter's memory bands.
struct ChapterSection: View {
    let title: String
    let rangeText: String?
    let memories: [MemoryRow]
    let axis: ClosedRange<Int>?
    let actions: MemoryRowActions
    /// Stories placed in this chapter (M5), after the loose memories.
    var stories: [StoryRow] = []
    var expanded: Set<StoryID> = []
    var onToggleStory: (StoryID) -> Void = { _ in }
    var storyActions = StoryRowActions(rename: { _ in }, split: { _ in })

    var body: some View {
        Section {
            if let axis { YearAxis(years: axis).listRowBackground(Color.clear).listRowSeparator(.hidden) }
            ForEach(memories) { row in
                MemoryRowView(row: row, axis: axis, actions: actions)
            }
            ForEach(stories) { story in
                StoryRowView(row: story, axis: axis, expanded: expanded.contains(story.id), onToggle: { onToggleStory(story.id) },
                             actions: actions, storyActions: storyActions)
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
