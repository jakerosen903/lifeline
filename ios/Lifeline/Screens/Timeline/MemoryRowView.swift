import LifelineKit
import SwiftUI

/// What the "…" menu and a long-press on a memory row can do.
struct MemoryRowActions {
    let open: (MemoryRow) -> Void
    let addToCollection: (MemoryRow) -> Void
    let addDate: (MemoryRow) -> Void
    let hide: (MemoryRow) -> Void
    let setExcluded: (MemoryRow, Bool) -> Void
    let delete: (MemoryRow) -> Void
    /// Stories (M5): offered on every row; "Take out" only when the row is in one.
    var moveToStory: (MemoryRow) -> Void = { _ in }
    var takeOutOfStory: (MemoryRow) -> Void = { _ in }
}

/// A memory row: its text (tap opens it), its chapter tag, its Check-this tags, and the visible
/// "…" menu that offers everything the long-press does.
struct MemoryRowView: View {
    let row: MemoryRow
    let actions: MemoryRowActions
    /// On the shelf the two useful moves are shown inline; the "…" menu stays (M4.1).
    var inline = false
    var placement: MemoryTextPlacement = .list

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // Full width, so the "…" menu sits at the trailing edge whatever the title's length, and a
                // rectangle to hit: a plain button otherwise answers only on its text, not between the lines.
                Button { actions.open(row) } label: {
                    MemoryText(row: row, placement: placement)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timeline.memory")
                // Outside the button, so the tag is an element of its own; the button's label names the chapter too.
                if let chapterTitle = row.chapterTitle {
                    ChapterTag(title: chapterTitle).padding(.bottom, 6)
                }
                if !row.checkThis.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(row.checkThis, id: \.label) { CheckThisTag(tag: $0) }
                    }
                    .padding(.bottom, 6)
                }
                if inline {
                    HStack(spacing: 8) {
                        Button("Add a date", systemImage: "calendar") { actions.addDate(row) }
                            .accessibilityIdentifier("row.addDate")
                        Button("Add to a collection", systemImage: "square.stack") { actions.addToCollection(row) }
                            .accessibilityIdentifier("row.addCollection")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.oliveOnFill)
                    .font(.caption)
                    .padding(.bottom, 6)
                }
            }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 8)
                    .frame(minWidth: 44, minHeight: 44, alignment: .top)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("row.more")
        }
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Add to a collection…", systemImage: "square.stack") { actions.addToCollection(row) }
        Button("Move to another story…", systemImage: "text.book.closed") { actions.moveToStory(row) }
            .accessibilityIdentifier("row.moveToStory")
        if row.storyID != nil {
            Button("Take out of its story", systemImage: "rectangle.portrait.and.arrow.right") { actions.takeOutOfStory(row) }
                .accessibilityIdentifier("row.takeOut")
        }
        Divider()
        Button("Hide from timeline", systemImage: "eye.slash") { actions.hide(row) }
            .accessibilityIdentifier("row.hide")
        if row.memory.excludedFromAI {
            Button("Include in AI processing", systemImage: "sparkles") { actions.setExcluded(row, false) }
                .accessibilityIdentifier("row.exclude")
        } else {
            Button("Exclude from AI processing", systemImage: "sparkles.slash") { actions.setExcluded(row, true) }
                .accessibilityIdentifier("row.exclude")
        }
        Button("Delete…", systemImage: "trash", role: .destructive) { actions.delete(row) }
            .accessibilityIdentifier("row.delete")
    }
}
