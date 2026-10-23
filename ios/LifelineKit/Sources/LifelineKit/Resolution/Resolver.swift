import Foundation

/// A memory as the resolver sees it: id, title (a target name), its current range, and where
/// its words are (so a floating target can borrow the span).
public struct MemoryRef: Sendable, Equatable {
    public struct Span: Sendable, Equatable {
        public var segmentID: SegmentID
        public var startMs: Milliseconds
        public var endMs: Milliseconds
        public init(segmentID: SegmentID, startMs: Milliseconds, endMs: Milliseconds) {
            self.segmentID = segmentID; self.startMs = startMs; self.endMs = endMs
        }
    }
    public var id: MemoryID
    public var title: String
    public var range: TimeRange
    public var primarySpan: Span

    public init(id: MemoryID, title: String, range: TimeRange, primarySpan: Span) {
        self.id = id; self.title = title; self.range = range; self.primarySpan = primarySpan
    }
}

public struct ResolverInput: Sendable {
    public var memories: [MemoryRef]
    public var anchors: [Anchor]
    public var birthDate: CivilDate?
    public var chapters: [Chapter]
    public var config: ResolverConfig

    public init(memories: [MemoryRef], anchors: [Anchor], birthDate: CivilDate?, chapters: [Chapter], config: ResolverConfig = .default) {
        self.memories = memories; self.anchors = anchors; self.birthDate = birthDate; self.chapters = chapters; self.config = config
    }
}

/// A target phrase no memory or chapter matches. The runner makes a memory for it.
public struct FloatingTarget: Sendable, Equatable {
    public var phrase: String
    public var anchorID: AnchorID
    public var fromMemory: MemoryID
}

public struct CuriosityDraft: Sendable, Equatable {
    public var kind: CuriosityKind
    public var text: String
    public var payoffCount: Int
    public var sourceMemoryID: MemoryID?
    public var targetPhrase: String?
    public var targetMemoryID: MemoryID?
}

public struct ResolverOutput: Sendable, Equatable {
    /// New ranges for memories whose stored range differs. Confirmed memories never appear.
    public var placements: [MemoryID: TimeRange]
    public var floating: [FloatingTarget]
    public var curiosity: [CuriosityDraft]
    public var resolvedAnchorIDs: Set<AnchorID>
}

/// Spec §8, as a pure function. Rules run in order for every memory, and the whole pass repeats
/// until nothing changes, so a chain places in one call and a cycle ends. The same input always
/// gives the same output, which is what makes a full re-run equal the incremental runs.
public enum Resolver {
    public static func resolve(_ input: ResolverInput) -> ResolverOutput {
        var ranges: [MemoryID: TimeRange] = Dictionary(uniqueKeysWithValues: input.memories.map { ($0.id, $0.range) })
        let original = ranges
        var resolved = Set<AnchorID>()
        let anchorsByMemory = Dictionary(grouping: input.anchors, by: \.memoryID)

        // Rules 1 and 2 need nothing but the anchor; rule 3 needs a placed target. Iterate.
        for _ in 0...(input.memories.count + 1) {
            var changed = false
            for memory in input.memories where !(original[memory.id]?.isConfirmed ?? false) {
                let anchors = anchorsByMemory[memory.id] ?? []
                var candidates: [(Anchor, TimeRange)] = []
                for anchor in anchors {
                    if let range = range(for: anchor, input: input, ranges: ranges) { candidates.append((anchor, range)) }
                }
                guard !candidates.isEmpty else { continue }
                let (combined, used) = combine(candidates)
                if ranges[memory.id] != combined {
                    ranges[memory.id] = combined
                    changed = true
                }
                resolved.formUnion(used)
            }
            if !changed { break }
        }

        // Rule 4: relative anchors whose target is still not placed.
        var floating: [FloatingTarget] = []
        var seenPhrases = Set<String>()
        var payoff: [String: (count: Int, memories: Set<MemoryID>, targetID: MemoryID?)] = [:]
        for anchor in input.anchors where anchor.isRelative && !resolved.contains(anchor.id) {
            guard let phrase = anchor.targetText?.trimmingCharacters(in: .whitespacesAndNewlines), !phrase.isEmpty else { continue }
            let key = PeopleRepository.normalize(phrase)
            let target = findTarget(phrase, in: input)
            if target == nil, !isChapter(phrase, input), seenPhrases.insert(key).inserted {
                floating.append(FloatingTarget(phrase: phrase, anchorID: anchor.id, fromMemory: anchor.memoryID))
            }
            var entry = payoff[key] ?? (0, [], target?.id)
            if entry.memories.insert(anchor.memoryID).inserted { entry.count += 1 }
            if entry.targetID == nil { entry.targetID = target?.id }
            payoff[key] = entry
        }
        let curiosity = payoff
            .map { key, entry in
                CuriosityDraft(kind: .unresolvedAnchor, text: originalPhrase(for: key, in: input.anchors), payoffCount: entry.count,
                               sourceMemoryID: entry.memories.sorted { $0.rawValue < $1.rawValue }.first,
                               targetPhrase: originalPhrase(for: key, in: input.anchors), targetMemoryID: entry.targetID)
            }
            .sorted { ($0.payoffCount, $1.text) > ($1.payoffCount, $0.text) }

        var placements: [MemoryID: TimeRange] = [:]
        for (id, range) in ranges where range != original[id] { placements[id] = range }
        return ResolverOutput(placements: placements, floating: floating, curiosity: curiosity, resolvedAnchorIDs: resolved)
    }

    // MARK: - One anchor

    private static func range(for anchor: Anchor, input: ResolverInput, ranges: [MemoryID: TimeRange]) -> TimeRange? {
        let config = input.config
        switch anchor.relation {
        case .absolute:
            return AnchorPhrase.parseAbsolute(anchor.phrase, value: anchor.value)
        case .age:
            guard let birth = input.birthDate, let age = AnchorPhrase.parseAge(anchor.phrase, value: anchor.value) else { return nil }
            return ageRange(age, birth: birth, config: config, evidence: anchor.phrase)
        case .before, .after, .during, .sameYearAs:
            guard let phrase = anchor.targetText, let target = targetRange(phrase, input: input, ranges: ranges), target.isPlaced else { return nil }
            var out: TimeRange
            switch anchor.relation {
            case .after: out = target.widened(by: config.relativeSlackYears, toward: .later)
            case .before: out = target.widened(by: config.relativeSlackYears, toward: .earlier)
            default: out = target
            }
            out.likelyStart = nil; out.likelyEnd = nil
            out.granularity = .year
            out.origin = .inferred
            out.evidenceText = anchor.phrase
            return out
        }
    }

    static func ageRange(_ age: AgeSpan, birth: CivilDate, config: ResolverConfig, evidence: String) -> TimeRange {
        switch age {
        case .years(let from, let to):
            return TimeRange.span(birth.adding(years: from), birth.adding(years: to + config.ageBandYears).adding(days: -1),
                                  granularity: .year, origin: .inferred, evidence: evidence)
        case .approximate(let center, let slack):
            return TimeRange.span(birth.adding(years: center - slack), birth.adding(years: center + slack + config.ageBandYears).adding(days: -1),
                                  granularity: .year, origin: .inferred, evidence: evidence)
        case .grade(let n):
            let startYear = birth.year + n + config.gradeOffsetYears
            return TimeRange.span(.first(ofMonth: config.schoolYearStartMonth, year: startYear),
                                  .last(ofMonth: config.schoolYearEndMonth, year: startYear + 1),
                                  granularity: .year, origin: .inferred, evidence: evidence)
        }
    }

    /// Several anchors on one memory: intersect what agrees. When two disagree, the first stated
    /// range wins and the rest stay unresolved; with no stated range, the first anchor wins.
    private static func combine(_ candidates: [(Anchor, TimeRange)]) -> (TimeRange, Set<AnchorID>) {
        let ordered = candidates.sorted { a, b in (a.1.origin == .stated ? 0 : 1) < (b.1.origin == .stated ? 0 : 1) }
        var result = ordered[0].1
        var used: Set<AnchorID> = [ordered[0].0.id]
        for (anchor, range) in ordered.dropFirst() {
            if let narrowed = result.intersect(range) {
                // Keep the finer evidence: the narrower band's origin and phrase.
                let finer = (range.latest!.year - range.earliest!.year) < (result.latest!.year - result.earliest!.year) ? range : result
                result = narrowed
                result.origin = finer.origin
                result.evidenceText = finer.evidenceText
                result.granularity = finer.granularity
                used.insert(anchor.id)
            }
        }
        return (result, used)
    }

    // MARK: - Targets

    private static func targetRange(_ phrase: String, input: ResolverInput, ranges: [MemoryID: TimeRange]) -> TimeRange? {
        if let memory = findTarget(phrase, in: input) { return ranges[memory.id] }
        if let chapter = input.chapters.first(where: { matches($0.title ?? "", phrase) }) { return chapter.range }
        return nil
    }

    /// A placed match beats an unplaced one, so a stand-in never shadows the told story.
    private static func findTarget(_ phrase: String, in input: ResolverInput) -> MemoryRef? {
        let hits = input.memories.filter { matches($0.title, phrase) || ($0.range.evidenceText.map { matches($0, phrase) } ?? false) }
        return hits.first(where: \.range.isPlaced) ?? hits.first
    }

    private static func isChapter(_ phrase: String, _ input: ResolverInput) -> Bool {
        input.chapters.contains { matches($0.title ?? "", phrase) }
    }

    /// A target phrase names a memory when it is the title, or the title contains it, or it
    /// contains the title, by the same whole-word rule the validator uses.
    static func matches(_ title: String, _ phrase: String) -> Bool {
        let t = OutputValidator.tokens(title), p = OutputValidator.tokens(phrase)
        guard !t.isEmpty, !p.isEmpty else { return false }
        return OutputValidator.contains(t, phrase) || OutputValidator.contains(p, title)
    }

    private static func originalPhrase(for key: String, in anchors: [Anchor]) -> String {
        anchors.lazy.compactMap(\.targetText).first { PeopleRepository.normalize($0) == key }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? key
    }
}

extension Anchor {
    public var isRelative: Bool {
        switch relation {
        case .before, .after, .during, .sameYearAs: true
        case .age, .absolute: false
        }
    }
}
