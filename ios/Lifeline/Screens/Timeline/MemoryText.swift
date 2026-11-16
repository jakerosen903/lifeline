import LifelineKit
import SwiftUI

/// Where a memory's text sits, which decides how its date and its voice length are written.
enum MemoryTextPlacement: Equatable {
    /// Off the spine (the shelf, a collection, a story's members): the voice length beside the title,
    /// then date, age and people in one line.
    case list
    /// On the spine: the margin shows the years, so the date line writes only what they leave out
    /// (`SpineLayout.Stop.rowDateText`, nil for nothing) and the age. The title has the full width;
    /// the voice length has a line of its own. At the accessibility text sizes the margin closes,
    /// and the full date goes above the title instead.
    case spine(dateText: String?)
}

/// A memory's words: the title, the honest date text and the people. Text only; the chapter tag
/// sits beside it in the row, as its own accessibility element.
struct MemoryText: View {
    let row: MemoryRow
    var placement: MemoryTextPlacement = .list
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch placement {
            case .list:
                titleWithVoiceLength
                Text(row.subtitle).font(.subheadline).foregroundStyle(dateColour)
            case .spine(let dateText):
                if typeSize.isAccessibilitySize {
                    dateLine(row.rangeText)
                    title
                } else {
                    title
                    dateLine(dateText)
                }
                if !row.people.isEmpty {
                    Text(row.people.joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                voiceLength
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

    private var title: some View {
        Text(row.memory.title)
            .font(.system(.headline, design: .serif))
            .foregroundStyle(Theme.ink)
            .spineMarkOnFirstLine()
    }

    /// Off the spine: the voice length beside the title when both fit on one line, else under it. A
    /// narrow column (a story's members, indented beside the spine) or a large text size would
    /// otherwise make the row wider than the list and push it off the side.
    private var titleWithVoiceLength: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title.fixedSize()
                Spacer(minLength: 0)
                voiceLength.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                voiceLength
            }
        }
    }

    @ViewBuilder private var voiceLength: some View {
        if !row.durationText.isEmpty {
            Text("\(row.durationText) in your voice").font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    /// The date on the spine and the age when an age placed it; just the age when the margin holds
    /// the years; nothing when there is neither.
    @ViewBuilder private func dateLine(_ date: String?) -> some View {
        let parts = [date, row.ageText].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(dateColour)
        }
    }

    /// Ochre for a guess or no date; ink for what the person said.
    private var dateColour: Color { row.isGuess || !row.memory.range.isPlaced ? Theme.ochreText : Theme.ink.opacity(0.8) }
}
