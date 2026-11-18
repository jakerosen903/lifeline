import LifelineKit
import SwiftUI

/// What the "…" menu on a story row can do.
struct StoryRowActions {
    let rename: (StoryRow) -> Void
    let split: (StoryRow) -> Void
}

/// A story as one row: its title (or "{first} + {n} more") and its span from the dated members
/// (M5). A tap opens or folds it.
///
/// Its members are laid out by the two places that list a story: `SpineRowView` (beside the spine)
/// and `ShelfSection`.
struct StoryRowView: View {
    let row: StoryRow
    let expanded: Bool
    let onToggle: () -> Void
    let storyActions: StoryRowActions
    /// On the spine at the accessibility sizes the margin closes, so the date goes above the title.
    var isOnSpine = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var dateText: String { row.isPlaced ? row.span.displayText : "no dates yet" }
    private var datesAboveTitle: Bool { isOnSpine && typeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
                        Text("Story").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    if datesAboveTitle { date }
                    Text(row.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .spineMarkOnFirstLine()
                    if !datesAboveTitle { date }
                }
                .padding(.vertical, 6)
                // The whole row up to the "…" menu opens or folds the story, not only its words.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title) · \(dateText) · \(row.members.count) moments")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline.story")
            Menu {
                Button("Rename…", systemImage: "pencil") { storyActions.rename(row) }
                    .accessibilityIdentifier("story.rename")
                Button("Split…", systemImage: "scissors") { storyActions.split(row) }
                    .accessibilityIdentifier("story.split")
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.secondaryText).padding(.top, 8)
                    .frame(minWidth: 44, minHeight: 44, alignment: .top)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("story.more")
        }
    }

    private var date: some View {
        Text(dateText).font(.subheadline).foregroundStyle(Theme.ochreText)
    }
}

/// "Split…": the members to take into a new, untitled story.
struct SplitStorySheet: View {
    let row: StoryRow
    let onConfirm: ([MemoryID]) -> Void
    @State private var taking: Set<MemoryID> = []
    @Environment(\.dismiss) private var dismiss

    private var canSplit: Bool { !taking.isEmpty && taking.count < row.members.count }

    var body: some View {
        NavigationStack {
            List(row.members) { member in
                Button {
                    if taking.contains(member.id) { taking.remove(member.id) } else { taking.insert(member.id) }
                } label: {
                    HStack {
                        Text(member.memory.title).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: taking.contains(member.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.olive)
                    }
                }
                .accessibilityIdentifier("split.member")
            }
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle("Take into a new story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { onConfirm(row.members.map(\.id).filter { taking.contains($0) }); dismiss() }
                        .disabled(!canSplit)
                        .accessibilityIdentifier("split.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// "Move to another story…": the other stories, newest first.
struct MoveToStorySheet: View {
    let stories: [Story]
    let onChoose: (StoryID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if stories.isEmpty {
                    Text("No other story yet.").foregroundStyle(Theme.secondaryText)
                }
                ForEach(stories) { story in
                    Button(story.title ?? "Untitled story") { onChoose(story.id); dismiss() }
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("move.story")
                }
            }
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle("Which story?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
