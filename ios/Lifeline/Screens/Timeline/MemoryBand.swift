import LifelineKit
import SwiftUI

/// A memory on the year axis: a light bar for the possible band, a darker one for the likely
/// band, a dot for a stated day or month. Below it the title and the honest range text.
struct MemoryBand: View {
    let row: MemoryRow
    let axis: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let axis, let lo = row.memory.range.earliest, let hi = row.memory.range.latest {
                GeometryReader { geo in
                    let width = geo.size.width
                    let x0 = YearAxis.x(for: lo.year, in: axis, width: width)
                    let x1 = YearAxis.x(for: hi.year + 1, in: axis, width: width)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.olive.opacity(row.isGuess ? 0.25 : 0.6))
                            .frame(width: max(6, x1 - x0), height: 6).offset(x: x0)
                        if let ls = row.memory.range.likelyStart, let le = row.memory.range.likelyEnd {
                            let lx0 = YearAxis.x(for: ls.year, in: axis, width: width), lx1 = YearAxis.x(for: le.year + 1, in: axis, width: width)
                            Capsule().fill(Theme.olive.opacity(0.7)).frame(width: max(6, lx1 - lx0), height: 6).offset(x: lx0)
                        }
                        if row.memory.range.granularity == .day || row.memory.range.granularity == .month {
                            Circle().fill(Theme.olive).frame(width: 10, height: 10).offset(x: x0 - 2)
                        }
                    }
                }
                .frame(height: 10)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.memory.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if !row.durationText.isEmpty {
                    Text("\(row.durationText) in your voice").font(.caption).foregroundStyle(Theme.stone)
                }
            }
            Text(row.subtitle)
                .font(.subheadline)
                .foregroundStyle(row.isGuess || !row.memory.range.isPlaced ? Theme.ochre : Theme.ink.opacity(0.8))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.memory.title) · \(row.subtitle)")
    }
}

/// What the "…" menu and a long-press on a memory row can do.
struct MemoryRowActions {
    let open: (MemoryRow) -> Void
    let newChapter: (MemoryRow) -> Void
    let addToCollection: (MemoryRow) -> Void
    let addDate: (MemoryRow) -> Void
    let hide: (MemoryRow) -> Void
    let setExcluded: (MemoryRow, Bool) -> Void
    let delete: (MemoryRow) -> Void
}

/// A memory row: the band (tap opens it), its Check-this tags, and the visible "…" menu that
/// offers everything the long-press does.
struct MemoryRowView: View {
    let row: MemoryRow
    let axis: ClosedRange<Int>?
    let actions: MemoryRowActions

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Button { actions.open(row) } label: { MemoryBand(row: row, axis: axis) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timeline.memory")
                if !row.checkThis.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(row.checkThis, id: \.label) { CheckThisTag(tag: $0) }
                    }
                    .padding(.bottom, 6)
                }
            }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.stone)
                    .padding(.top, 8)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("row.more")
        }
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("New chapter from here", systemImage: "book") { actions.newChapter(row) }
        Button("Add to a collection…", systemImage: "square.stack") { actions.addToCollection(row) }
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
