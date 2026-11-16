import LifelineKit
import SwiftUI

/// Where a memory's text sits, which decides how its date is written.
enum MemoryTextPlacement: Equatable {
    /// Off the spine (the shelf, a collection, a story's members): date, age and people in one line.
    case list
    /// On the spine: the margin shows the years, so the row writes only what they leave out
    /// (`SpineLayout.Stop.rowDateText`), nil for nothing. At the accessibility text sizes the margin
    /// closes, and the row writes the full date above the title instead.
    case spine(dateText: String?)
}

/// A memory's words: the title, the honest date text and the people. Text only; the chapter tag
/// sits beside it in the row, as its own accessibility element.
struct MemoryText: View {
    let row: MemoryRow
    var placement: MemoryTextPlacement = .list
    @Environment(\.dynamicTypeSize) private var typeSize
    /// From the title's first baseline up to where the mark's centre sits: about half a capital.
    @ScaledMetric(relativeTo: .headline) private var markLift: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch placement {
            case .list:
                title
                Text(row.subtitle).font(.subheadline).foregroundStyle(dateColour)
            case .spine(let dateText):
                if typeSize.isAccessibilitySize {
                    dateLine(row.rangeText)
                    title
                } else {
                    title
                    if let dateText { dateLine(dateText) }
                }
                if !row.people.isEmpty {
                    Text(row.people.joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "{title} · {date · age · people}", and " · {chapter}" when the moment has a tag.
    private var accessibilityText: String {
        var text = "\(row.memory.title) · \(row.subtitle)"
        if let chapterTitle = row.chapterTitle { text += " · \(chapterTitle)" }
        return text
    }

    /// The title with its length in the person's voice beside it; under it at the accessibility
    /// sizes, where side by side would leave the title one word a line.
    private var title: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(row.memory.title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
                // The spine's mark lines up with the title's first line, however far the title wraps.
                .alignmentGuide(.spineMark) { [lift = markLift] in $0[.firstTextBaseline] - lift }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if !row.durationText.isEmpty {
                Text("\(row.durationText) in your voice").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// The date on the spine, with the age when an age placed it.
    private func dateLine(_ date: String) -> some View {
        Text(([date] + [row.ageText].compactMap { $0 }).joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(dateColour)
    }

    /// Ochre for a guess or no date; ink for what the person said.
    private var dateColour: Color { row.isGuess || !row.memory.range.isPlaced ? Theme.ochreText : Theme.ink.opacity(0.8) }
}

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
                Button { actions.open(row) } label: { MemoryText(row: row, placement: placement) }
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
