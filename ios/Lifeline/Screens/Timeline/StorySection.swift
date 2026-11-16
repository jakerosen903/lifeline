import LifelineKit
import SwiftUI

/// What the "…" menu on a story row can do.
struct StoryRowActions {
    let rename: (StoryRow) -> Void
    let split: (StoryRow) -> Void
}

/// A story as one row: its title (or "{first} + {n} more") and its span from the dated members
/// (M5). A tap opens or folds it; whoever lists the story lays its members out under it.
struct StoryRowView: View {
    let row: StoryRow
    let expanded: Bool
    let onToggle: () -> Void
    let storyActions: StoryRowActions
    /// From the title's first baseline up to where the mark's centre sits: about half a capital.
    @ScaledMetric(relativeTo: .headline) private var markLift: CGFloat = 6

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
                        Text("Story").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Text(row.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Theme.ink)
                        // On the spine the mark lines up with the title's first line.
                        .alignmentGuide(.spineMark) { [lift = markLift] in $0[.firstTextBaseline] - lift }
                    Text(row.isPlaced ? row.span.displayText : "no dates yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ochreText)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title) · \(row.isPlaced ? row.span.displayText : "no dates yet") · \(row.members.count) moments")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline.story")
            Spacer(minLength: 0)
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
