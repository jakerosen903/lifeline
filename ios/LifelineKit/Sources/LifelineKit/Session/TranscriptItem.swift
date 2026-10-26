import Foundation

/// One line of a session's transcript as the person reads it: their words, or what the interviewer said.
public enum TranscriptItem: Equatable, Sendable, Identifiable {
    case segment(Segment)
    case turn(InterviewerTurn)

    public var id: String {
        switch self {
        case .segment(let segment): "segment-\(segment.id.rawValue)"
        case .turn(let turn): "turn-\(turn.id.rawValue)"
        }
    }

    var startMs: Milliseconds {
        switch self {
        case .segment(let segment): segment.startMs
        case .turn(let turn): turn.startMs
        }
    }

    /// Segments and turns in file order. At the same start the turn goes first: the person spoke over
    /// it, so it was said first (the opening and a first word both at 0 are the usual case).
    public static func merge(segments: [Segment], turns: [InterviewerTurn]) -> [TranscriptItem] {
        let items = turns.map(TranscriptItem.turn) + segments.map(TranscriptItem.segment)
        // Stable: equal starts keep turns before segments, and each list keeps its own order.
        return items.enumerated().sorted { ($0.element.startMs, $0.offset) < ($1.element.startMs, $1.offset) }.map(\.element)
    }
}
