import Foundation

/// One moment on the landing: a kept memory or a possible one, with the span that plays it.
public struct LandingRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var quote: String
    public var segmentID: SegmentID
    public var play: MsRange
    public var isKept: Bool

    public init(id: String, title: String, quote: String, segmentID: SegmentID, play: MsRange, isKept: Bool) {
        self.id = id; self.title = title; self.quote = quote; self.segmentID = segmentID; self.play = play; self.isKept = isKept
    }
}

/// R6 Landing and R4 FirstPayoff, the pure parts. The landing says the recording is saved, plays
/// a few moments back, and never asks for a decision. Nothing here waits for sorting.
public enum Landing {
    public static let cap = 5

    /// Kept memories (by their first span) and possible ones (the whole moment), in session
    /// order, capped. Returns the rows and how many more there are.
    public static func rows(kept: [(Memory, MemorySpan)], possible: [(Candidate, MemoryOut)], segments: [Segment])
        -> (rows: [LandingRow], more: Int) {
        let index = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        var all: [(order: (Int, Int), row: LandingRow)] = []
        for (memory, span) in kept {
            let seg = index[span.segmentID]
            all.append(((seg?.index ?? .max, span.startMs),
                        LandingRow(id: "memory:\(memory.id.rawValue)", title: memory.title, quote: memory.summaryQuote,
                                   segmentID: span.segmentID, play: MsRange(start: span.startMs, end: span.endMs), isKept: true)))
        }
        for (candidate, out) in possible {
            guard let seg = index[candidate.segmentID] else { continue }
            all.append(((seg.index, seg.endMs + candidate.ordinal),   // after any kept span of the same moment
                        LandingRow(id: "candidate:\(candidate.id.rawValue)", title: out.title, quote: out.quote,
                                   segmentID: seg.id, play: seg.range, isKept: false)))
        }
        let ordered = all.sorted { $0.order < $1.order }.map(\.row)
        return (Array(ordered.prefix(cap)), max(0, ordered.count - cap))
    }

    public static func stillSorting(pendingSegments: Int) -> String? {
        pendingSegments > 0 ? "Still sorting: \(pendingSegments) more" : nil
    }

    /// Neutral after a heavy session; otherwise the top open question, phrased as an opener.
    public static func closingLine(topCuriosity: CuriosityItem?, heavy: Bool) -> String {
        if heavy { return "Thank you. That's enough for today." }
        if let topCuriosity { return "Next time, if you like: \(OpeningChooser.phrase(for: topCuriosity))" }
        return "Thank you for today."
    }

    public static func isFirstSession(sessionCount: Int) -> Bool { sessionCount == 1 }

    public static func headline(first: Bool, heavy: Bool) -> String {
        first && !heavy ? "Your first story is saved. Hear it back." : "Your recording is saved."
    }
}
