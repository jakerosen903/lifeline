/// What the spine shows for an ordered list of dated things. Pure: it stores nothing.
public enum SpineLayout {
    public enum Mark: Equatable, Sendable { case solidDot, dashedDot, dashedCapsule }

    public struct Gap: Equatable, Sendable {
        public let years: Int
        /// 0...4, from the table in the plan's decision 6. The view turns a unit into points.
        public let units: Int
        /// "3 years", from three years up; nil below.
        public let label: String?
        public var isDashed: Bool { label != nil }
    }

    public struct Stop: Equatable, Sendable {
        public let id: String
        public let mark: Mark
        /// "1999" or "2008–10".
        public let years: String
        /// "around" for a dashed dot; nil otherwise, and always nil for a confirmed relation, whose
        /// far edge is the builder's slack and never reads as a fact.
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
        var previous: Stop?
        var previousWasRelation = false
        var previousPeriod: LifePeriod?
        for item in items where item.range.isDated {
            let shown = shownYears(of: item.range)
            let mark = mark(for: item.range, shown: shown)
            let years = TimeRange.yearSpan(shown.start, shown.end)
            let isRelation = isConfirmedRelation(item.range)
            let qualifier = mark == .dashedDot && !isRelation ? "around" : nil
            let period = LifePeriod.containing(year: shown.start, birthYear: birthYear)
            let stop = Stop(
                id: item.id, mark: mark, years: years, qualifier: qualifier,
                showsYears: !isRelation && (previousWasRelation || !(previous?.years == years && previous?.qualifier == qualifier)),
                rowDateText: rowDateText(for: item.range, years: years),
                gapAbove: latestEnd.map { gap(years: max(0, shown.start - $0)) },
                periodAbove: period == previousPeriod ? nil : period)
            stops.append(stop)
            previous = stop
            previousWasRelation = isRelation
            previousPeriod = period
            latestEnd = max(latestEnd ?? shown.end, shown.end)
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

    /// The gap table (decision 6): units 0, 0, 1, 2, 3, 4 by years; a label from three years.
    static func gap(years: Int) -> Gap {
        let units: Int
        switch years {
        case ..<2: units = 0
        case 2: units = 1
        case 3...4: units = 2
        case 5...9: units = 3
        default: units = 4
        }
        return Gap(years: years, units: units, label: years >= 3 ? "\(years) years" : nil)
    }

    // MARK: - Helpers

    /// The likely band when both its ends exist, else the possible band.
    private static func shownYears(of range: TimeRange) -> (start: Int, end: Int) {
        if let start = range.likelyStart, let end = range.likelyEnd { return (start.year, end.year) }
        return (range.earliest?.year ?? 0, range.latest?.year ?? 0)  // isDated guarantees both
    }

    /// A confirmed relation ("before Graduation (2004)"): the case where `displayText` is the evidence.
    private static func isConfirmedRelation(_ range: TimeRange) -> Bool {
        guard range.origin == .confirmed, let evidence = range.evidenceText else { return false }
        return TimeRange.isRelationEvidence(evidence)
    }

    /// Decision 5: more than one shown year is a capsule; one year is solid only when it reads as said.
    private static func mark(for range: TimeRange, shown: (start: Int, end: Int)) -> Mark {
        if shown.end > shown.start { return .dashedCapsule }
        return range.readsAsSaid ? .solidDot : .dashedDot
    }

    /// The row repeats the date only when it says more than the margin's years and qualifier.
    private static func rowDateText(for range: TimeRange, years: String) -> String? {
        let text = range.displayText
        return text == years || text == "around " + years ? nil : text
    }
}
