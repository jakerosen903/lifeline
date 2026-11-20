import LifelineKit
import SwiftUI

/// One stop on the spine, top to bottom: the gap above it, the period waypoint that starts at it,
/// then the row itself: the margin with the years, the mark on the spine, and the moment or story.
/// An open story's members follow as list rows of their own, beside the spine, without marks.
///
/// The spine is one 2-point ochre line. Each part draws its own piece at the same x, and the list
/// rows touch (the screen gives them no vertical insets), so the pieces join into one line. It
/// starts at the first stop's mark and ends at the last stop's mark, or, when the last stop is an
/// open story, at the bottom of its last member.
struct SpineRowView: View {
    let row: SpineRow
    let isFirst: Bool
    let isLast: Bool
    let expanded: Bool
    let onToggleStory: () -> Void
    let actions: MemoryRowActions
    let storyActions: StoryRowActions
    /// Where the list's rows can be seen, and the slack the card's own height needs (`OnScreenReport`).
    let screenArea: ScreenArea
    /// True when the stop's row comes on screen, false when it leaves; the card's frame follows.
    let onScreenChange: (Bool) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Wide enough for "2008–10" at the row's text size.
    @ScaledMetric(relativeTo: .footnote) private var marginWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let gap = row.stop.gapAbove, gap.units > 0 { SpineGap(gap: gap, geometry: geometry) }
            if let period = row.stop.periodAbove { SpineWaypoint(period: period, geometry: geometry, drawsSpine: !isFirst) }
            // Only the stop's own row reports: not the gap or the period above it, and not an open
            // story's members below. Members can have dates; they do not report in this PR (ruling R7).
            stopRow.reportsOnScreen(in: screenArea, onChange: onScreenChange)
        }
        // List rows of their own, so each member keeps its own long-press menu (Hide, Exclude, Delete):
        // the list lifts a context menu to its cell. The screen's row modifiers apply to each of them.
        ForEach(openMembers) { member in
            // Members carry no mark and keep their full date text in the row, as off the spine.
            MemoryRowView(row: member, actions: actions)
                .padding(.leading, geometry.contentLeading + 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) { SpineLine(dashed: false, x: geometry.spineX) }
        }
    }

    /// An open story's members; none for a moment or a folded story.
    private var openMembers: [MemoryRow] {
        guard case .story(let story) = row.content, expanded else { return [] }
        return story.members
    }

    /// The spine runs on below the mark towards a next stop, or beside an open story's members.
    private var spineRunsOnBelowMark: Bool { !isLast || !openMembers.isEmpty }

    /// The margin closes at the accessibility text sizes; the row then writes the full date itself.
    private var geometry: SpineGeometry {
        SpineGeometry(marginWidth: typeSize.isAccessibilitySize ? nil : marginWidth)
    }

    private var stopRow: some View {
        HStack(alignment: .spineMark, spacing: 0) {
            if let width = geometry.marginWidth {
                margin.frame(width: width, alignment: .trailing)
            }
            SpineMark(mark: row.stop.mark)
                .alignmentGuide(.spineMark) { _ in SpineMark.size / 2 }
                .anchorPreference(key: MarkCenter.self, value: .center) { $0 }
                .padding(.leading, geometry.markLeading)
                .accessibilityHidden(true)
            content
                .padding(.leading, SpineGeometry.contentGap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .backgroundPreferenceValue(MarkCenter.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let markY = proxy[anchor].y
                    let top = isFirst ? markY : 0
                    let bottom = spineRunsOnBelowMark ? proxy.size.height : markY
                    SpineLine(dashed: false, x: geometry.spineX)
                        .frame(height: max(0, bottom - top))
                        .offset(y: top)
                }
            }
        }
    }

    /// "around" over "1999", or nothing when the stop above shows the same years.
    private var margin: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if row.stop.showsYears {
                if let qualifier = row.stop.qualifier {
                    Text(qualifier).font(.caption2.weight(.semibold))
                }
                Text(row.stop.years)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .alignmentGuide(.spineMark) { $0[VerticalAlignment.center] }
            }
        }
        .foregroundStyle(Theme.ochreText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // The row's label already says the date: VoiceOver hears it once (decision 12).
        .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch row.content {
        case .memory(let memory):
            MemoryRowView(row: memory, actions: actions, placement: .spine(dateText: row.stop.rowDateText))
        case .story(let story):
            StoryRowView(row: story, expanded: expanded, onToggle: onToggleStory, storyActions: storyActions, isOnSpine: true)
        }
    }
}

/// Where the spine and the content sit across a row, so every part draws the spine at one x.
private struct SpineGeometry {
    /// The margin's width; nil when the margin closes.
    let marginWidth: CGFloat?
    static let marginGap: CGFloat = 6
    /// Room before the mark when the margin is closed.
    static let closedLeading: CGFloat = 4
    static let contentGap: CGFloat = 10

    var markLeading: CGFloat { marginWidth == nil ? Self.closedLeading : Self.marginGap }
    var spineX: CGFloat { (marginWidth ?? 0) + markLeading + SpineMark.size / 2 }
    var contentLeading: CGFloat { spineX + SpineMark.size / 2 + Self.contentGap }
}

/// The space above a stop: longer for more years, dashed with "3 years" from three years up.
private struct SpineGap: View {
    let gap: SpineLayout.Gap
    let geometry: SpineGeometry
    private static let pointsPerUnit: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(height: CGFloat(gap.units) * Self.pointsPerUnit)
            if let label = gap.label {
                // Time only: no invitation, no "nothing happened" (PRINCIPLES 9).
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 4)
                    .padding(.leading, geometry.contentLeading)
                    .accessibilityIdentifier("timeline.gap")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) { SpineLine(dashed: gap.isDashed, x: geometry.spineX) }
    }
}

/// "Teens · by your age", or "The 1980s": where a period starts. A header for VoiceOver.
private struct SpineWaypoint: View {
    let period: LifePeriod
    let geometry: SpineGeometry
    /// False above the first stop: the spine starts at its mark.
    let drawsSpine: Bool

    /// What follows the name: " · by your age" for a period of the person's age, nothing for a decade.
    private var suffix: String { period.byAge ? " · by your age" : "" }

    var body: some View {
        label
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .padding(.leading, geometry.contentLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(period.name + suffix)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("timeline.period")
            .background(alignment: .leading) { if drawsSpine { SpineLine(dashed: false, x: geometry.spineX) } }
    }

    /// The same words as the accessibility label, with the name in semibold.
    private var label: Text { Text("\(Text(period.name).fontWeight(.semibold))\(suffix)") }
}

/// A piece of the spine: the full height of whatever it is behind, centred on `x`.
private struct SpineLine: View {
    let dashed: Bool
    let x: CGFloat
    private static let width: CGFloat = 2

    var body: some View {
        VerticalLine()
            .stroke(Theme.ochre, style: StrokeStyle(lineWidth: Self.width, dash: dashed ? [5, 4] : []))
            .frame(width: Self.width)
            .offset(x: x - Self.width / 2)
            .accessibilityHidden(true)
    }
}

private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

/// The centre of a stop's mark, so the row's piece of spine can start or end there.
private struct MarkCenter: PreferenceKey {
    static var defaultValue: SwiftUI.Anchor<CGPoint>? { nil }
    static func reduce(value: inout SwiftUI.Anchor<CGPoint>?, nextValue: () -> SwiftUI.Anchor<CGPoint>?) { value = value ?? nextValue() }
}
