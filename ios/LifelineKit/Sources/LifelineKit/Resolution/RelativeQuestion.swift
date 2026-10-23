import Foundation

/// One question that can narrow a memory's range, phrased as a choice between things the
/// owner said. Never a date.
public struct RelativeQuestion: Equatable, Sendable {
    public struct Choice: Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var resultingRange: TimeRange
        /// The sentence stored as the range's evidence ("before Graduation (2004)").
        public var evidence: String
    }

    public var memoryID: MemoryID
    public var prompt: String
    public var choices: [Choice]
    /// The anchor this question settles, when it came from one.
    public var anchorID: AnchorID?
}

public enum RelativeQuestions {
    /// The one question a memory admits, or nil. Order of preference:
    /// (a) an unresolved relative anchor whose target is placed: before or after it;
    /// (b) a placed guess wider than one year with a placed sibling inside the band: same year as it;
    /// nothing else. A birthday alone would make a date question and is not used.
    public static func question(for memory: MemoryRef, anchors: [Anchor], placed: [MemoryRef], siblings: [MemoryRef],
                                birthDate: CivilDate?, config: ResolverConfig) -> RelativeQuestion? {
        guard !memory.range.isConfirmed else { return nil }
        if let q = beforeOrAfter(memory, anchors: anchors, placed: placed, config: config) { return q }
        return sameYear(memory, siblings: siblings)
    }

    /// The choice's range as a confirmed range with the choice as its evidence.
    public static func apply(_ choice: RelativeQuestion.Choice, to memory: MemoryRef) -> TimeRange {
        var range = choice.resultingRange
        range.origin = .confirmed
        range.evidenceText = choice.evidence
        return range
    }

    // MARK: - (a)

    private static func beforeOrAfter(_ memory: MemoryRef, anchors: [Anchor], placed: [MemoryRef], config: ResolverConfig) -> RelativeQuestion? {
        for anchor in anchors where anchor.memoryID == memory.id && anchor.isRelative && !anchor.resolved {
            guard let target = target(of: anchor, in: placed), target.range.isPlaced else { continue }
            let year = yearLabel(target.range)
            let before = narrowed(memory.range, by: target.range.widened(by: config.relativeSlackYears, toward: .earlier).asGuess(anchor.phrase))
            let after = narrowed(memory.range, by: target.range.widened(by: config.relativeSlackYears, toward: .later).asGuess(anchor.phrase))
            guard let before, let after else { continue }
            return RelativeQuestion(
                memoryID: memory.id,
                prompt: "Was this before or after \(target.title)?",
                choices: [
                    .init(id: "before", label: "Before (\(year))", resultingRange: before, evidence: "before \(target.title) (\(year))"),
                    .init(id: "after", label: "After (\(year))", resultingRange: after, evidence: "after \(target.title) (\(year))"),
                ],
                anchorID: anchor.id)
        }
        return nil
    }

    private static func target(of anchor: Anchor, in placed: [MemoryRef]) -> MemoryRef? {
        if let id = anchor.targetID, let hit = placed.first(where: { $0.id.rawValue == id }) { return hit }
        if let phrase = anchor.targetText { return placed.first { Resolver.matches($0.title, phrase) } }
        return nil
    }

    // MARK: - (b)

    private static func sameYear(_ memory: MemoryRef, siblings: [MemoryRef]) -> RelativeQuestion? {
        let band = memory.range
        guard band.origin == .inferred, let lo = band.earliest, let hi = band.latest, hi.year > lo.year else { return nil }
        guard let sibling = siblings.first(where: { s in
            s.id != memory.id && s.range.isPlaced && s.range.origin != .inferred
                && s.range.earliest.map { $0 >= lo } == true && s.range.latest.map { $0 <= hi } == true
                && s.range.earliest?.year == s.range.latest?.year
        }), let sYear = sibling.range.earliest?.year else { return nil }

        let yes = TimeRange.year(sYear, origin: .inferred, evidence: sibling.title)
        let earlierSide = sYear > lo.year ? TimeRange.span(lo, .lastOfYear(sYear - 1), granularity: .year, origin: .inferred, evidence: nil) : nil
        let laterSide = sYear < hi.year ? TimeRange.span(.firstOfYear(sYear + 1), hi, granularity: .year, origin: .inferred, evidence: nil) : nil
        let no: TimeRange
        switch (earlierSide, laterSide) {
        case (let e?, let l?): no = (l.latest!.year - l.earliest!.year) >= (e.latest!.year - e.earliest!.year) ? l : e
        case (let e?, nil): no = e
        case (nil, let l?): no = l
        case (nil, nil): return nil
        }
        return RelativeQuestion(
            memoryID: memory.id,
            prompt: "Was this the same year as \(sibling.title)?",
            choices: [.init(id: "yes", label: "Yes (\(sYear))", resultingRange: yes, evidence: "the same year as \(sibling.title)"),
                      .init(id: "no", label: "No", resultingRange: no, evidence: "not the same year as \(sibling.title)")],
            anchorID: nil)
    }

    // MARK: - Helpers

    /// The band restricted to what the memory already allows, when it is placed.
    private static func narrowed(_ own: TimeRange, by band: TimeRange) -> TimeRange? {
        guard own.isPlaced else { return band }
        guard var out = band.intersect(own) else { return nil }
        out.origin = .inferred
        return out
    }

    private static func yearLabel(_ range: TimeRange) -> String {
        guard let a = range.earliest?.year, let b = range.latest?.year else { return "" }
        return TimeRange.yearSpan(a, b)
    }
}

private extension TimeRange {
    func asGuess(_ evidence: String) -> TimeRange {
        var out = self
        out.likelyStart = nil; out.likelyEnd = nil
        out.granularity = .year
        out.origin = .inferred
        out.evidenceText = evidence
        return out
    }
}
