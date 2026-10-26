import Foundation

/// The safety part of the interviewer's own call for a segment: the same two questions the extractor's
/// flags answer, asked before the app may speak about it.
public struct SafetyCheck: Equatable, Sendable {
    public var disclosure: DisclosureKind
    public var wantsToStop: Bool

    public init(disclosure: DisclosureKind, wantsToStop: Bool) {
        self.disclosure = disclosure; self.wantsToStop = wantsToStop
    }

    public var isClean: Bool { disclosure == .none && !wantsToStop }
}

/// What the policy hears. A nil check means the interviewer call failed.
public enum TurnInput: Equatable, Sendable {
    case speechStarted, partial, userPaused
    /// Only segments that keep words of the person's; a segment emptied of the app's words is never stored.
    case segmentStored(SegmentID)
    case interviewerCheck(SegmentID, SafetyCheck?)
    case extractorFlags(SegmentID, Flags)
    case stage(Stage)
    case quiet(Bool)
    /// The app's own playback.
    case turnStarted(TurnKind), turnEnded
}

/// A turn the app wants to speak. `requestedAt` is when its words were asked for, for turns that wait on a call.
public struct TurnOffer: Equatable, Sendable {
    public var kind: TurnKind
    public var source: TurnSource
    public var text: String
    public var requestedAt: Duration?

    public init(kind: TurnKind, source: TurnSource, text: String, requestedAt: Duration? = nil) {
        self.kind = kind; self.source = source; self.text = text; self.requestedAt = requestedAt
    }
}

public enum QuietReason: Equatable, Sendable {
    case personSpeaking, appSpeaking, heavy, quiet, gate, stale, noSegmentSince, questionTooSoon, windDown, quickStory, openingTooLate
}

public enum TurnDecision: Equatable, Sendable {
    case speak
    case stayQuiet(QuietReason)
}

/// Spec M8 "Turn policy": events and a clock in, one decision out. Silence is the default; every rule
/// can only hold a turn back. Pure: `at` is the time since the session started.
public struct TurnPolicy: Equatable, Sendable {
    public let kind: SessionKind
    public let config: ArcConfig

    private enum CheckResult: Equatable, Sendable { case failed, returned(SafetyCheck) }

    private var speechOpen = false
    private var lastSpeechStart: Duration?
    private var lastPartial: Duration?
    private var lastPause: Duration?
    private var appSpeaking = false
    private var newestSegment: SegmentID?
    /// The pause that closed the newest segment: the reply grace counts from it.
    private var newestSegmentPause: Duration?
    private var checks: [SegmentID: CheckResult] = [:]
    private var flags: [SegmentID: Flags] = [:]
    /// Rule 2: the extractor flagged a disclosure or a wish to stop on some segment.
    private var heavy = false
    /// Rule 4: an interviewer check on some segment was not clean.
    private var uncleanCheck = false
    private var stage: Stage = .open
    private var quiet = false
    /// The last two spoken turns, newest last. Rule 7.
    private var recentTurns: [TurnKind] = []
    /// True before the first turn, so the opening needs no segment. Rule 6.
    private var segmentSinceLastTurn = true

    public init(kind: SessionKind, config: ArcConfig) {
        self.kind = kind; self.config = config
    }

    public mutating func observe(_ input: TurnInput, at now: Duration) {
        switch input {
        case .speechStarted:
            speechOpen = true; lastSpeechStart = now
        case .partial:
            lastPartial = now
        case .userPaused:
            speechOpen = false; lastPause = now
        case .segmentStored(let id):
            newestSegment = id; newestSegmentPause = lastPause ?? now; segmentSinceLastTurn = true
        case .interviewerCheck(let id, let check):
            // A duplicate check for a segment keeps the first; the latch below never reopens anyway.
            if checks[id] == nil { checks[id] = check.map(CheckResult.returned) ?? .failed }
            if let check, !check.isClean { uncleanCheck = true }
        case .extractorFlags(let id, let segmentFlags):
            flags[id] = segmentFlags
            if segmentFlags.isHeavy { heavy = true }
        case .stage(let newStage):
            stage = newStage
        case .quiet(let isQuiet):
            quiet = isQuiet
        case .turnStarted(let turnKind):
            appSpeaking = true; segmentSinceLastTurn = false
            recentTurns = Array((recentTurns + [turnKind]).suffix(2))
        case .turnEnded:
            appSpeaking = false
        }
    }

    /// Precedence as in the spec: speaking, heavy, quiet, gate, stale, rules 6, 7 and 10, then quick story.
    public func decide(_ offer: TurnOffer, at now: Duration) -> TurnDecision {
        let isModel = offer.source == .model
        // The arc's answer to a disclosure or a wish to stop: never gated, never held by quiet or rule 6.
        let answersTheArc = offer.kind == .disclosure || offer.kind == .earlyWindDown

        if personSpeaking(at: now) { return .stayQuiet(.personSpeaking) }
        if appSpeaking { return .stayQuiet(.appSpeaking) }
        if isModel && heavy { return .stayQuiet(.heavy) }
        if quiet && !answersTheArc { return .stayQuiet(.quiet) }
        if offer.kind != .opening && !answersTheArc && !gateOpen(for: offer) { return .stayQuiet(.gate) }
        if let requested = offer.requestedAt, let spoke = lastSpeechStart, spoke > requested { return .stayQuiet(.stale) }
        if offer.kind == .opening && lastSpeechStart != nil { return .stayQuiet(.openingTooLate) }
        if !answersTheArc && !segmentSinceLastTurn { return .stayQuiet(.noSegmentSince) }
        if offer.kind.isQuestion && recentTurns.contains(where: \.isQuestion) { return .stayQuiet(.questionTooSoon) }
        // `ended` holds model turns too: the session is landing.
        if isModel && stage != .open { return .stayQuiet(.windDown) }
        if kind == .quick && offer.kind != .opening && !answersTheArc { return .stayQuiet(.quickStory) }
        return .speak
    }

    /// The newest stored segment, once `replyGrace` has passed since its pause with no speech and no turn
    /// since, and only if no check for it has come back yet (it was not asked about already).
    public func segmentAwaitingReply(at now: Duration) -> SegmentID? {
        guard kind == .settleIn, !quiet, !heavy, !uncleanCheck, stage == .open,
              let segment = newestSegment, let pause = newestSegmentPause,
              segmentSinceLastTurn, checks[segment] == nil,
              !personSpeaking(at: now), !appSpeaking,
              now - pause >= config.replyGrace else { return nil }
        if let spoke = lastSpeechStart, spoke > pause { return nil }
        return segment
    }

    /// Rule 1: a start with no pause after it, or a partial inside `partialHoldsFloor`.
    private func personSpeaking(at now: Duration) -> Bool {
        if speechOpen { return true }
        guard let partial = lastPartial else { return false }
        return now - partial < config.partialHoldsFloor
    }

    /// Rule 4: a clean interviewer check of the newest segment, and clean extractor flags if they arrived.
    /// One unclean check or heavy flag on any segment closes the gate to model turns and the wrap-up for good.
    private func gateOpen(for offer: TurnOffer) -> Bool {
        if (offer.source == .model || offer.kind == .wrapUp) && (uncleanCheck || heavy) { return false }
        guard let segment = newestSegment, case .returned(let check) = checks[segment], check.isClean else { return false }
        return flags[segment].map { !$0.isHeavy } ?? true
    }
}
