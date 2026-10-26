import Foundation

/// What the session view shows about the interviewer.
public struct InterviewerState: Equatable, Sendable {
    public var isQuiet: Bool
    public init(isQuiet: Bool) { self.isQuiet = isQuiet }
}

/// Feeds the session's events to a `TurnPolicy` and offers it turns. A turn the policy lets through
/// goes to `speak` (`SessionRecorder.speak` in the app), which returns false when the voice refused it. This task offers fixed turns only: the
/// opening, and the arc's answer to a disclosure or a wish to stop. `now` is the time since the
/// session started; `sleep` waits on the same clock, so tests drive both by hand.
public actor InterviewerLoop {
    public nonisolated let states: AsyncStream<InterviewerState>
    private let stateContinuation: AsyncStream<InterviewerState>.Continuation

    private let config: ArcConfig
    private let speak: @Sendable (TurnDraft) async -> Bool
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
    /// The voice session reported `playing` as started. A draft that ends unstarted was never heard.
    private var started = false
    /// Counts drafts handed to `speak`, so a refusal that returns late knows whether its draft is still out.
    private var handCount = 0
    private var playingHand = 0
    /// Between `.paused` or `.interrupted` and `.resumed`. Saves offers the voice would refuse;
    /// a refused draft is requeued anyway, so nothing depends on this matching the session's state.
    private var suspended = false
    /// The person paused after their newest speech start, so a refusal for speaking is a partial's hold.
    private var pausedSinceSpeech = false
    /// A retry is waiting out a partial's hold on the floor. One at a time.
    private var floorRetryArmed = false
    /// Offers waiting out the reply grace or a partial's hold.
    private var retries: [UUID: Task<Void, Never>] = [:]
    /// How often each draft ended before its playback started. A voice that keeps failing must
    /// not hold the queue for the whole session.
    private var unstartedEnds: [TurnDraft: Int] = [:]
    private static let maxUnstartedEnds = 3

    public init(kind: SessionKind, config: ArcConfig,
                speak: @escaping @Sendable (TurnDraft) async -> Bool,
                now: @escaping @Sendable () -> Duration,
                sleep: @escaping @Sendable (Duration) async -> Void) {
        self.config = config
        self.speak = speak; self.now = now; self.sleep = sleep
        policy = TurnPolicy(kind: kind, config: config)
        (states, stateContinuation) = AsyncStream.makeStream()
    }

    /// The opening is offered once, now or never: a refused opening (the person already spoke) is dropped.
    public func captureStarted(opening: String) async {
        guard !openingOffered, !ended, !suspended else { return }
        openingOffered = true
        let draft = TurnDraft(kind: .opening, source: .fixed, text: opening)
        guard playing == nil, decide(draft) == .speak else { return }
        await hand(draft)
    }

    public func voice(_ event: VoiceEvent) async {
        switch event {
        case .speechStarted:
            observe(.speechStarted)
            pausedSinceSpeech = false
        case .transcriptPartial:
            observe(.partial)
        case .userPaused:
            observe(.userPaused)
            pausedSinceSpeech = true
            scheduleRetry(after: config.replyGrace)
        case .turnStarted:
            // A start with no draft handed out is not one of this loop's turns.
            guard let playing else { return }
            started = true
            observe(.turnStarted(playing.kind))
        case .turnEnded:
            observe(.turnEnded)
            let unstarted = started ? nil : playing
            playing = nil; started = false
            // A started turn that was cut is not spoken again.
            guard let unstarted else { await offerPending(); return }
            // Cut before it started (a pause, an interruption, barge-in, a voice that failed): it was
            // never heard. It waits at the front for the next resume, pause's grace or floor retry;
            // an offer now would feed a failing voice the same draft in a loop.
            endedUnstarted(unstarted)
        case .paused, .interrupted:
            suspended = true
        case .resumed:
            suspended = false
            await offerPending()
        case .transcriptFinal, .segmentClosed, .failed:
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

    /// For tests: returns when the retries out at the call have finished. A retry they schedule
    /// is still asleep, so it is not waited for.
    func retriesSettled() async {
        for task in Array(retries.values) { await task.value }
    }

    // MARK: Private

    private func observe(_ input: TurnInput) {
        policy.observe(input, at: now())
    }

    private func decide(_ draft: TurnDraft) -> TurnDecision {
        policy.decide(TurnOffer(kind: draft.kind, source: draft.source, text: draft.text), at: now())
    }

    /// A draft that was never heard goes back to the front, except the opening, which is now or never.
    private func requeue(_ draft: TurnDraft) {
        guard draft.kind != .opening else { return }
        pending.insert(draft, at: 0)
    }

    /// Requeues a draft that was never heard, until it has ended unstarted `maxUnstartedEnds` times.
    private func endedUnstarted(_ draft: TurnDraft) {
        let count = unstartedEnds[draft, default: 0] + 1
        unstartedEnds[draft] = count
        guard count < Self.maxUnstartedEnds else {
            print("[interviewer] dropped a \(draft.kind.rawValue) turn: it ended \(count) times before playback started")
            return
        }
        requeue(draft)
    }

    /// The disclosure text goes before a wind-down line that is still waiting, so a later present
    /// danger's crisis line is not held behind it. The wind-down line follows, once per session.
    /// After present danger, a past disclosure adds nothing: the 988 text already covers it.
    private func queueDisclosure(_ kind: DisclosureKind) {
        guard kind != .none else { return }
        if !disclosuresQueued.contains(kind), !(kind == .past && disclosuresQueued.contains(.present)),
           let text = spokenDisclosure(kind) {
            disclosuresQueued.insert(kind)
            let draft = TurnDraft(kind: .disclosure, source: .fixed, text: text)
            let index = pending.firstIndex { $0.kind == .earlyWindDown } ?? pending.endIndex
            pending.insert(draft, at: index)
        }
        queueWindDown()
    }

    /// The text is a bundled resource that a test checks, so a load failure is a build fault.
    /// The wind-down line is still spoken.
    private func spokenDisclosure(_ kind: DisclosureKind) -> String? {
        do {
            return try FixedResponses.spokenDisclosure(kind)
        } catch {
            print("[interviewer] could not load the spoken \(kind.rawValue) disclosure: \(error)")
            assertionFailure("spoken disclosure missing: \(error)")
            return nil
        }
    }

    private func queueWindDown() {
        guard !windDownQueued else { return }
        windDownQueued = true
        pending.append(TurnDraft(kind: .earlyWindDown, source: .fixed, text: FixedTurns.earlyWindDown))
    }

    /// Offers the oldest pending turn. A refusal keeps it pending for the next pause, turn end or resume.
    private func offerPending() async {
        guard !ended, !suspended, playing == nil, let next = pending.first else { return }
        let decision = decide(next)
        if decision == .speak {
            pending.removeFirst()
            await hand(next)
        } else if next.kind == .opening {
            // A refused opening is never kept: it must not block the turns behind it.
            pending.removeFirst()
            await offerPending()
        } else if decision == .stayQuiet(.personSpeaking), pausedSinceSpeech, !floorRetryArmed {
            // A partial after the pause holds the floor, and no later pause may come to wake us.
            floorRetryArmed = true
            scheduleRetry(after: config.partialHoldsFloor, clearsFloorRetry: true)
        }
    }

    /// `playing` is set before the await, so an event that arrives meanwhile offers nothing on top.
    /// A refused draft is requeued but not offered again at once: the voice would refuse it again
    /// until a resume, a pause's grace, a turn's end or the floor retry.
    private func hand(_ draft: TurnDraft) async {
        handCount += 1
        let hand = handCount
        playing = draft; started = false; playingHand = hand
        guard !(await speak(draft)), playingHand == hand, playing != nil else { return }
        playing = nil
        requeue(draft)
    }

    /// Offer again after `delay`, then judge afresh: the person may have spoken, or the session
    /// paused or ended, in the meantime.
    private func scheduleRetry(after delay: Duration, clearsFloorRetry: Bool = false) {
        let id = UUID()
        retries[id] = Task {
            await sleep(delay)
            if clearsFloorRetry { floorRetryArmed = false }
            await offerPending()
            retries[id] = nil
        }
    }
}
