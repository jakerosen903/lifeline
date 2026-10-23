/// Tunable values for the energy gate. Defaults come from the V1 design spec.
public struct SegmenterConfig: Sendable, Equatable {
    /// Silence this long after speech closes the segment.
    public var pauseThresholdMs: Milliseconds
    /// A segment with less accumulated speech than this is abandoned, not emitted.
    public var minSegmentSpeechMs: Milliseconds
    /// Level at or above this counts as speech.
    public var speechThresholdDb: Float
    /// A segment is force-closed once it reaches this length.
    public var maxSegmentMs: Milliseconds

    public init(pauseThresholdMs: Milliseconds = 1_800, minSegmentSpeechMs: Milliseconds = 3_000,
                speechThresholdDb: Float = -40, maxSegmentMs: Milliseconds = 90_000) {
        self.pauseThresholdMs = pauseThresholdMs
        self.minSegmentSpeechMs = minSegmentSpeechMs
        self.speechThresholdDb = speechThresholdDb
        self.maxSegmentMs = maxSegmentMs
    }
}

public enum SegmenterEvent: Equatable, Sendable {
    case speechStarted(atMs: Milliseconds)
    case segmentEnded(MsRange)
    /// A pause ended (speech resumed). Logged for calibrating the later end-of-thought model.
    case pauseObserved(ms: Milliseconds)
}

/// A pure state machine that turns per-chunk audio levels into segment boundaries.
/// It holds no clock and does no I/O; the caller feeds chunks in file-time order.
public struct Segmenter: Sendable {
    private enum State: Equatable {
        case idle
        /// Inside a segment. `speechMs` is the accumulated speech; `lastSpeechEnd` is where the
        /// segment will end if the current or a later pause closes it.
        case open(segmentStart: Milliseconds, speechMs: Milliseconds, lastSpeechEnd: Milliseconds, pauseStart: Milliseconds?)
    }

    public let config: SegmenterConfig
    private var state: State = .idle

    public init(config: SegmenterConfig = .init()) {
        self.config = config
    }

    public mutating func observe(levelDb: Float, startMs: Milliseconds, durationMs: Milliseconds) -> [SegmenterEvent] {
        let isSpeech = levelDb >= config.speechThresholdDb
        let endMs = startMs + durationMs

        switch state {
        case .idle:
            guard isSpeech else { return [] }
            state = .open(segmentStart: startMs, speechMs: durationMs, lastSpeechEnd: endMs, pauseStart: nil)
            return [.speechStarted(atMs: startMs)]

        case .open(let segmentStart, var speechMs, var lastSpeechEnd, var pauseStart):
            var events: [SegmenterEvent] = []
            if isSpeech {
                if let p = pauseStart {
                    events.append(.pauseObserved(ms: startMs - p))
                    pauseStart = nil
                }
                speechMs += durationMs
                lastSpeechEnd = endMs
            } else if pauseStart == nil {
                pauseStart = startMs
            }

            if let p = pauseStart, endMs - p >= config.pauseThresholdMs {
                // The pause is long enough: close or abandon, then wait for speech.
                if speechMs >= config.minSegmentSpeechMs {
                    events.append(.segmentEnded(MsRange(start: segmentStart, end: lastSpeechEnd)))
                }
                state = .idle
                return events
            }

            if lastSpeechEnd - segmentStart >= config.maxSegmentMs {
                // Too long: force-close at this chunk and open the next segment immediately.
                events.append(.segmentEnded(MsRange(start: segmentStart, end: lastSpeechEnd)))
                state = .open(segmentStart: lastSpeechEnd, speechMs: 0, lastSpeechEnd: lastSpeechEnd, pauseStart: nil)
                events.append(.speechStarted(atMs: lastSpeechEnd))
                return events
            }

            state = .open(segmentStart: segmentStart, speechMs: speechMs, lastSpeechEnd: lastSpeechEnd, pauseStart: pauseStart)
            return events
        }
    }

    /// Closes an open segment (if it has enough speech) at `atMs` or at the last speech end,
    /// whichever is earlier. Used at stop and at interruptions. Idempotent.
    public mutating func flush(atMs: Milliseconds) -> [SegmenterEvent] {
        guard case .open(let segmentStart, let speechMs, let lastSpeechEnd, _) = state else { return [] }
        state = .idle
        guard speechMs >= config.minSegmentSpeechMs else { return [] }
        return [.segmentEnded(MsRange(start: segmentStart, end: min(atMs, lastSpeechEnd)))]
    }
}
