/// What the spine shows for an ordered list of dated things. Pure: it stores nothing.
public enum SpineLayout {
    public enum Mark: Equatable, Sendable { case solidDot, dashedDot, dashedCapsule }

    public struct Gap: Equatable, Sendable {
        public let years: Int
        /// 0...4, from the table in the plan's decision 6. The view turns a unit into points.
        public let units: Int
        /// "3 years", from three years up; nil below. Also nil when the gap is measured from or to
        /// the band of a confirmed relation: that band's edge is the builder's slack (ruling R18).
        public let label: String?
        /// Dashed exactly when the gap has a label.
        public var isDashed: Bool { label != nil }
    }

    public struct Stop: Equatable, Sendable {
        public let id: String
        public let mark: Mark
        /// "1999" or "2008–10".
        public let years: String
        /// The first and last year the margin shows, as numbers; nil for a confirmed relation, whose
        /// margin shows no years. Derived from the same years as `years`.
        public let yearSpan: ClosedRange<Int>?
        /// "around" for a dashed dot, and for a capsule whose date text is "around {years}" (an age
        /// guess over two calendar years, ruling R17); nil otherwise. Always nil for a confirmed
        /// relation, whose far edge is the builder's slack and never reads as a fact.
        public let qualifier: String?
        /// False when the stop above shows the same years (the year is written once), and always
        /// false for a confirmed relation (its row says it in words). True for the stop directly
        /// below a relation: nothing is written above to compare with.
        public let showsYears: Bool
        /// The full date text, when it says more than the margin does; nil otherwise.
        public let rowDateText: String?
        /// The space above this stop; nil for the first stop.
        public let gapAbove: Gap?
        /// The period that starts at this stop; nil when the stop above is in the same one.
        public let periodAbove: LifePeriod?
    }

    /// `items` must be in display order. An item whose range is not dated is skipped: the view model
    /// filters first, so this only keeps the function total.
    public static func stops(for items: [(id: String, range: TimeRange)], birthYear: Int?) -> [Stop] {
        var stops: [Stop] = []
        var latestEnd: Int?  // the latest end of every stop so far: a range inside a range makes no gap after it
        var latestEndIsRelation = false  // the stop that owns `latestEnd` is a confirmed relation
        var previous: Stop?
        var previousWasRelation = false
        var previousPeriod: LifePeriod?
        for item in items where item.range.isDated {
            let shown = shownYears(of: item.range)
            let mark = mark(for: item.range, shown: shown)
            let years = TimeRange.yearSpan(shown.start, shown.end)
            let isRelation = item.range.isConfirmedRelation
            let qualifier = !isRelation && (mark == .dashedDot || item.range.displayText == around + " " + years) ? around : nil
            let period = LifePeriod.containing(year: placingDate(of: item.range)!.year, birthYear: birthYear)  // isDated guarantees a date
            let stop = Stop(
                id: item.id, mark: mark, years: years,
                yearSpan: isRelation ? nil : min(shown.start, shown.end)...max(shown.start, shown.end),
                qualifier: qualifier,
                showsYears: !isRelation && (previousWasRelation || !(previous?.years == years && previous?.qualifier == qualifier)),
                rowDateText: rowDateText(for: item.range, years: years),
                gapAbove: latestEnd.map { gap(years: max(0, shown.start - $0), labelled: !isRelation && !latestEndIsRelation) },
                periodAbove: period == previousPeriod ? nil : period)
            stops.append(stop)
            previous = stop
            previousWasRelation = isRelation
            previousPeriod = period
            if let end = latestEnd, shown.end <= end {
                // A stated end level with a relation's end makes that year a fact: the gap from it keeps its label.
                if shown.end == end { latestEndIsRelation = latestEndIsRelation && isRelation }
            } else {
                latestEnd = shown.end
                latestEndIsRelation = isRelation
            }
        }
        return stops
    }

    /// The range to lay a story out with: the span over its dated members. When that span is one
    /// year and every dated member reads as said, the year reads as said too (a solid dot);
    /// otherwise the derived span (one year is a dashed dot with "around"). For layout only: never stored.
    public static func storyRange(members: [TimeRange]) -> TimeRange {
        let dated = members.filter(\.isDated)
        let span = ChapterRepository.span(over: dated)
        // `span` is unplaced when `dated` is empty, so the guard also covers "no dated member".
        guard let earliest = span.earliest, let latest = span.latest else { return .unplaced }
        guard earliest.year == latest.year, dated.allSatisfy(\.readsAsSaid) else { return span }
        return .year(earliest.year, origin: .stated, evidence: nil)
    }

    /// The date the spine starts a dated range at: the likely start when the likely band has both ends,
    /// else the earliest. Nil when the range is not dated. The Things shelf groups by the same date.
    public static func placingDate(of range: TimeRange) -> CivilDate? {
        guard range.isDated else { return nil }
        if range.likelyStart != nil, range.likelyEnd != nil { return range.likelyStart }
        return range.earliest
    }

    /// The gap table (decision 6): units 0, 0, 1, 2, 3, 4 by years; a label from three years,
    /// unless `labelled` is false (a gap next to a relation keeps its space but states no number).
    static func gap(years: Int, labelled: Bool = true) -> Gap {
        let units: Int
        switch years {
        case ..<2: units = 0
        case 2: units = 1
        case 3...4: units = 2
        case 5...9: units = 3
        default: units = 4
        }
        return Gap(years: years, units: units, label: labelled && years >= 3 ? "\(years) years" : nil)
    }

    // MARK: - Helpers

    /// The qualifier the margin writes for a guess, and the prefix `displayText` gives one.
    private static let around = "around"

    /// The likely band when both its ends exist, else the possible band.
    private static func shownYears(of range: TimeRange) -> (start: Int, end: Int) {
        if let start = range.likelyStart, let end = range.likelyEnd { return (start.year, end.year) }
        return (range.earliest?.year ?? 0, range.latest?.year ?? 0)  // isDated guarantees both
    }

    /// Decision 5: more than one shown year is a capsule; one year is solid only when it reads as said.
    private static func mark(for range: TimeRange, shown: (start: Int, end: Int)) -> Mark {
        if shown.end > shown.start { return .dashedCapsule }
        return range.readsAsSaid ? .solidDot : .dashedDot
    }

    /// The row repeats the date only when it says more than the margin's years and qualifier.
    private static func rowDateText(for range: TimeRange, years: String) -> String? {
        let text = range.displayText
        return text == years || text == around + " " + years ? nil : text
    }
}
