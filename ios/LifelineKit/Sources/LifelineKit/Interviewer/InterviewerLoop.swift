import Foundation

/// What the session view shows about the interviewer.
public struct InterviewerState: Equatable, Sendable {
    public var isQuiet: Bool
    public init(isQuiet: Bool) { self.isQuiet = isQuiet }
}

/// Feeds the session's events to a `TurnPolicy` and offers it turns. A turn the policy lets through
/// goes to `speak` (`SessionRecorder.speak` in the app). This task offers fixed turns only: the
/// opening, and the arc's answer to a disclosure or a wish to stop. `now` is the time since the
/// session started; `sleep` waits on the same clock, so tests drive both by hand.
public actor InterviewerLoop {
    public nonisolated let states: AsyncStream<InterviewerState>
    private let stateContinuation: AsyncStream<InterviewerState>.Continuation

    private let config: ArcConfig
    private let speak: @Sendable (TurnDraft) async -> Void
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async -> Void

    private var policy: TurnPolicy
    private var isQuiet = false
    private var openingOffered = false
    /// Stage `ended`: the session is landing and nothing more is offered.
    private var ended = false
    /// Fixed turns the policy held back, oldest first. Each waits for the one before it to be played.
    private var pending: [TurnDraft] = []
    /// The disclosure texts and the wind-down line are queued once each per session.
    private var disclosuresQueued: Set<DisclosureKind> = []
    private var windDownQueued = false
    /// The draft handed to `speak` whose playback has not ended. The voice session reports turns by id
    /// only, so its kind comes from here. Nothing else is offered while it is set.
    private var playing: TurnDraft?
    /// Offers waiting out the reply grace after a pause.
    private var retries: [UUID: Task<Void, Never>] = [:]

    public init(kind: SessionKind, config: ArcConfig,
                speak: @escaping @Sendable (TurnDraft) async -> Void,
                now: @escaping @Sendable () -> Duration,
                sleep: @escaping @Sendable (Duration) async -> Void) {
        self.config = config
        self.speak = speak; self.now = now; self.sleep = sleep
        policy = TurnPolicy(kind: kind, config: config)
        (states, stateContinuation) = AsyncStream.makeStream()
    }

    /// The opening is offered once, now or never: a refused opening (the person already spoke) is dropped.
    public func captureStarted(opening: String) async {
        guard !openingOffered, !ended else { return }
        openingOffered = true
        let draft = TurnDraft(kind: .opening, source: .fixed, text: opening)
        guard playing == nil, decide(draft) == .speak else { return }
        await hand(draft)
    }

    public func voice(_ event: VoiceEvent) async {
        switch event {
        case .speechStarted:
            observe(.speechStarted)
        case .transcriptPartial:
            observe(.partial)
        case .userPaused:
            observe(.userPaused)
            retryAfterGrace()
        case .turnStarted:
            // A start with no draft handed out is not one of this loop's turns.
            guard let playing else { return }
            observe(.turnStarted(playing.kind))
        case .turnEnded:
            observe(.turnEnded)
            playing = nil
            await offerPending()
        case .transcriptFinal, .segmentClosed, .interrupted, .paused, .resumed, .failed:
            break
        }
    }

    public func segmentStored(_ id: SegmentID) {
        observe(.segmentStored(id))
    }

    public func flags(_ flags: Flags, segment: SegmentID) {
        observe(.extractorFlags(segment, flags))
    }

    /// The stage is observed before the effect, so the policy judges the effect's turn in its stage.
    public func arc(_ effect: ArcEffect, stage: Stage) async {
        observe(.stage(stage))
        if stage == .ended {
            ended = true
            pending = []
            return
        }
        switch effect {
        case .showDisclosureCard(let kind):
            queueDisclosure(kind)
        case .offerWrapUp(.wantsToStop):
            queueWindDown()
        case .offerWrapUp(.plannedLength):
            // Spoken only after a clean interviewer check (decision B), which a later task adds.
            break
        case .land:
            break
        }
        await offerPending()
    }

    public func setQuiet(_ quiet: Bool) {
        observe(.quiet(quiet))
        guard quiet != isQuiet else { return }
        isQuiet = quiet
        stateContinuation.yield(InterviewerState(isQuiet: quiet))
    }

    /// "Keep going" withdraws a wrap-up that has not been spoken. The arc's answer to a disclosure stays.
    public func keepGoing() {
        pending.removeAll { $0.kind == .wrapUp }
    }

    /// For tests: returns when every retry started so far has finished.
    func retriesSettled() async {
        while let task = retries.values.first {
            await task.value
        }
    }

    // MARK: Private

    private func observe(_ input: TurnInput) {
        policy.observe(input, at: now())
    }

    private func decide(_ draft: TurnDraft) -> TurnDecision {
        policy.decide(TurnOffer(kind: draft.kind, source: draft.source, text: draft.text), at: now())
    }

    /// The disclosure text goes before a wind-down line that is still waiting, so a later present
    /// danger's crisis line is not held behind it. The wind-down line follows, once per session.
    private func queueDisclosure(_ kind: DisclosureKind) {
        if !disclosuresQueued.contains(kind), let text = try? FixedResponses.spokenDisclosure(kind) {
            disclosuresQueued.insert(kind)
            let draft = TurnDraft(kind: .disclosure, source: .fixed, text: text)
            let index = pending.firstIndex { $0.kind == .earlyWindDown } ?? pending.endIndex
            pending.insert(draft, at: index)
        }
        if kind != .none { queueWindDown() }
    }

    private func queueWindDown() {
        guard !windDownQueued else { return }
        windDownQueued = true
        pending.append(TurnDraft(kind: .earlyWindDown, source: .fixed, text: FixedTurns.earlyWindDown))
    }

    /// Offers the oldest pending turn. A refusal keeps it pending for the next pause or turn end.
    private func offerPending() async {
        guard !ended, playing == nil, let next = pending.first, decide(next) == .speak else { return }
        pending.removeFirst()
        await hand(next)
    }

    /// `playing` is set before the await, so an event that arrives meanwhile offers nothing on top.
    private func hand(_ draft: TurnDraft) async {
        playing = draft
        await speak(draft)
    }

    /// The person may still be thinking: offer again once the grace has passed, then judge afresh,
    /// because the person may have spoken or the session ended in the meantime.
    private func retryAfterGrace() {
        let id = UUID()
        retries[id] = Task {
            await sleep(config.replyGrace)
            await offerPending()
            retries[id] = nil
        }
    }
}
