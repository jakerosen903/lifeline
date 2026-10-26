import Foundation

/// What the session view shows about the interviewer.
public struct InterviewerState: Equatable, Sendable {
    public var isQuiet: Bool
    public init(isQuiet: Bool) { self.isQuiet = isQuiet }
}

/// Feeds the session's events to a `TurnPolicy` and offers it turns. A turn the policy lets through
/// goes to `speak` (`SessionRecorder.speak` in the app), which returns false when the voice refused it.
/// Fixed turns: the opening, the arc's answer to a disclosure or a wish to stop, and the wrap-up.
/// Model turns: once `replyGrace` has passed after a story lands, one call to the interviewer asks for a
/// short reflection and the segment's safety check. `now` is the time since the session started;
/// `sleep` waits on the same clock, so tests drive both by hand.
public actor InterviewerLoop {
    public nonisolated let states: AsyncStream<InterviewerState>
    private let stateContinuation: AsyncStream<InterviewerState>.Continuation

    /// A turn waiting to be offered, or out at the voice. `requestedAt` is when the call for its words
    /// started, so the policy can drop it if the person spoke after that (rule 5).
    private struct Queued: Hashable {
        var draft: TurnDraft
        var requestedAt: Duration? = nil
        var kind: TurnKind { draft.kind }
    }

    private let config: ArcConfig
    /// Nil when there is no key: no calls, so nothing that waits for a check is spoken.
    private let service: (any InterviewerService)?
    /// The request for the newest stored segment, and every word of this session for `TurnChecks`.
    private let context: @Sendable () throws -> (InterviewerRequest, sessionWords: [String])
    private let speak: @Sendable (TurnDraft) async -> Bool
    /// Stops the turn that is playing (`SessionRecorder.interruptTurn` in the app). The voice reports its end.
    private let cut: @Sendable () async -> Void
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async -> Void
    private let log: @Sendable (String) -> Void

    private var policy: TurnPolicy
    private var isQuiet = false
    private var openingOffered = false
    /// Stage `ended`: the session is landing and nothing more is offered.
    private var ended = false
    /// Turns the policy held back. Disclosure texts first, then the wind-down line, then the gated turns;
    /// oldest first within each. Each waits for the one before it to be played.
    private var pending: [Queued] = []
    /// The disclosure texts and the wind-down line are queued once each per session.
    private var disclosuresQueued: Set<DisclosureKind> = []
    private var windDownQueued = false
    /// The turn handed to `speak` whose playback has not ended. The voice session reports turns by id
    /// only, so its kind comes from here. Nothing else is offered while it is set.
    private var playing: Queued?
    /// The voice session reported `playing` as started. A draft that ends unstarted was never heard.
    private var started = false
    /// Counts drafts handed to `speak`, so a refusal that returns late knows whether its draft is still out.
    private var handCount = 0
    private var playingHand = 0
    /// The hand this loop asked the voice to cut for a disclosure. A cut turn is never offered again.
    private var cutHand: Int?
    /// Between `.paused` or `.interrupted` and `.resumed`. Saves offers the voice would refuse;
    /// a refused draft is requeued anyway, so nothing depends on this matching the session's state.
    private var suspended = false
    /// The person paused after their newest speech start, so a refusal for speaking is a partial's hold.
    private var pausedSinceSpeech = false
    /// A retry is waiting out a partial's hold on the floor. One at a time.
    private var floorRetryArmed = false
    /// Offers and asks waiting out the reply grace or a partial's hold.
    private var retries: [UUID: Task<Void, Never>] = [:]
    /// How often each draft ended before its playback started. A voice that keeps failing must
    /// not hold the queue for the whole session. Only voice failures count: a pause or an
    /// interruption, and a turn that starts, reset the count.
    private var unstartedEnds: [Queued: Int] = [:]
    /// The draft whose unstarted end came last. The session reports the end before the
    /// `.paused` or `.interrupted` that caused it, so that event clears this draft's count.
    private var lastUnstarted: Queued?
    private static let maxUnstartedEnds = 3
    /// The newest stored segment and the newest pause, as the policy heard them. The reply grace counts from the pause.
    private var newestSegment: SegmentID?
    private var lastPause: Duration?
    /// The interviewer call that is out, and the segment it asks about. One call at a time.
    private var call: Task<Void, Never>?
    private var callSegment: SegmentID?

    public init(kind: SessionKind, config: ArcConfig,
                service: (any InterviewerService)?,
                context: @escaping @Sendable () throws -> (InterviewerRequest, sessionWords: [String]),
                speak: @escaping @Sendable (TurnDraft) async -> Bool,
                cut: @escaping @Sendable () async -> Void,
                now: @escaping @Sendable () -> Duration,
                sleep: @escaping @Sendable (Duration) async -> Void,
                log: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.config = config
        self.service = service; self.context = context
        self.speak = speak; self.cut = cut; self.now = now; self.sleep = sleep; self.log = log
        policy = TurnPolicy(kind: kind, config: config)
        (states, stateContinuation) = AsyncStream.makeStream()
    }

    /// The opening is offered once, now or never: a refused opening (the person already spoke) is dropped.
    public func captureStarted(opening: String) async {
        guard !openingOffered, !ended, !suspended else { return }
        openingOffered = true
        let turn = Queued(draft: TurnDraft(kind: .opening, source: .fixed, text: opening))
        guard playing == nil, decide(turn) == .speak else { return }
        await hand(turn)
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
            lastPause = now()
            scheduleRetry(after: config.replyGrace)
        case .turnStarted:
            // A start with no draft handed out is not one of this loop's turns.
            guard let playing else { return }
            started = true
            unstartedEnds[playing] = nil
            observe(.turnStarted(playing.kind))
        case .turnEnded:
            observe(.turnEnded)
            let wasCut = cutHand != nil && cutHand == playingHand
            let unstarted = started || wasCut ? nil : playing
            if wasCut, !started, let playing { log("[interviewer] dropped a \(playing.kind.rawValue) turn: cut for a disclosure") }
            playing = nil; started = false
            if wasCut { cutHand = nil }
            // A started turn that was cut is not spoken again.
            guard let unstarted else { await offerPending(); return }
            // Cut before it started (a pause, an interruption, barge-in, a voice that failed): it was
            // never heard. It waits at the front for the next resume, pause's grace or floor retry;
            // an offer now would feed a failing voice the same draft in a loop.
            endedUnstarted(unstarted)
        case .paused, .interrupted:
            suspended = true
            if let turn = lastUnstarted { unstartedEnds[turn] = nil }
        case .resumed:
            suspended = false
            await offerPending()
        case .transcriptFinal, .segmentClosed, .failed, .heard:
            break
        }
    }

    /// The grace counts from the pause before the segment, so a segment stored after that pause's
    /// wake is asked about at once; one stored before it gets its own wake at the same time.
    public func segmentStored(_ id: SegmentID) {
        observe(.segmentStored(id))
        newestSegment = id
        guard service != nil else { return }
        let delay = (lastPause ?? now()) + config.replyGrace - now()
        if delay > .zero {
            scheduleRetry(after: delay)
        } else {
            askIfAwaiting()
        }
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
            await answerDisclosure(kind)
        case .offerWrapUp(.wantsToStop):
            queueWindDown()
        case .offerWrapUp(.plannedLength):
            // Spoken only after a clean interviewer check (decision B). With no interviewer there is
            // no check, so it stays on screen only.
            if service != nil, !pending.contains(where: { $0.kind == .wrapUp }) {
                enqueue(Queued(draft: TurnDraft(kind: .wrapUp, source: .fixed, text: FixedTurns.wrapUp)))
            }
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
    /// is still asleep, so it is not waited for. A call they start is not waited for either.
    func retriesSettled() async {
        for task in Array(retries.values) { await task.value }
    }

    /// For tests: returns when no interviewer call is out, including a call that a reply starts.
    func callSettled() async {
        while let call { await call.value }
    }

    // MARK: Private

    private func observe(_ input: TurnInput) {
        policy.observe(input, at: now())
    }

    private func decide(_ turn: Queued) -> TurnDecision {
        policy.decide(TurnOffer(kind: turn.kind, source: turn.draft.source, text: turn.draft.text, requestedAt: turn.requestedAt), at: now())
    }

    /// The disclosure texts go first, then the wind-down line, then everything that waits for the gate.
    private static func rank(_ kind: TurnKind) -> Int {
        switch kind {
        case .disclosure: 0
        case .earlyWindDown: 1
        case .opening, .reflection, .question, .wrapUp, .aboutApp: 2
        }
    }

    /// A new turn goes behind the turns of its rank and ahead of every lower rank.
    private func enqueue(_ turn: Queued) {
        let rank = Self.rank(turn.kind)
        let index = pending.firstIndex { Self.rank($0.kind) > rank } ?? pending.endIndex
        pending.insert(turn, at: index)
    }

    /// A turn that was never heard goes to the front of its rank, except the opening, which is now or never.
    private func requeue(_ turn: Queued) {
        guard turn.kind != .opening else { return }
        let rank = Self.rank(turn.kind)
        let index = pending.firstIndex { Self.rank($0.kind) >= rank } ?? pending.endIndex
        pending.insert(turn, at: index)
    }

    /// Requeues a turn that was never heard, until it has ended unstarted `maxUnstartedEnds` times.
    private func endedUnstarted(_ turn: Queued) {
        let count = unstartedEnds[turn, default: 0] + 1
        unstartedEnds[turn] = count
        lastUnstarted = turn
        guard count < Self.maxUnstartedEnds else {
            log("[interviewer] dropped a \(turn.kind.rawValue) turn: it ended \(count) times before playback started")
            return
        }
        requeue(turn)
    }

    /// Spec Goal 4: the app stops any playback and speaks the fixed text. The disclosure text goes ahead
    /// of every other waiting turn, so a later present danger's crisis line is not held behind the
    /// wind-down line or a wrap-up. The wind-down line follows, once per session. After present danger,
    /// a past disclosure adds nothing: the 988 text already covers it. A playing disclosure text or
    /// wind-down line is the arc's own answer and plays out.
    private func answerDisclosure(_ kind: DisclosureKind) async {
        guard kind != .none else { return }
        if !disclosuresQueued.contains(kind), !(kind == .past && disclosuresQueued.contains(.present)),
           let text = spokenDisclosure(kind) {
            disclosuresQueued.insert(kind)
            enqueue(Queued(draft: TurnDraft(kind: .disclosure, source: .fixed, text: text)))
        }
        queueWindDown()
        guard let playing, playing.kind != .disclosure, playing.kind != .earlyWindDown, cutHand != playingHand else { return }
        cutHand = playingHand
        await cut()
    }

    /// The text is a bundled resource that a test checks, so a load failure is a build fault.
    /// The wind-down line is still spoken.
    private func spokenDisclosure(_ kind: DisclosureKind) -> String? {
        do {
            return try FixedResponses.spokenDisclosure(kind)
        } catch {
            log("[interviewer] could not load the spoken \(kind.rawValue) disclosure: \(error)")
            assertionFailure("spoken disclosure missing: \(error)")
            return nil
        }
    }

    private func queueWindDown() {
        guard !windDownQueued else { return }
        windDownQueued = true
        enqueue(Queued(draft: TurnDraft(kind: .earlyWindDown, source: .fixed, text: FixedTurns.earlyWindDown)))
    }

    /// Offers the first pending turn. A refused turn that keeps its place waits for the next pause,
    /// turn end, resume or reply; one that does not is dropped, and the turn behind it is offered.
    private func offerPending() async {
        while !ended, !suspended, playing == nil, let next = pending.first {
            guard case .stayQuiet(let reason) = decide(next) else {
                pending.removeFirst()
                await hand(next)
                return
            }
            guard waits(next, for: reason) else {
                pending.removeFirst()
                log("[interviewer] dropped a \(next.kind.rawValue) turn: \(reason)")
                continue
            }
            if reason == .personSpeaking, pausedSinceSpeech, !floorRetryArmed {
                // A partial after the pause holds the floor, and no later pause may come to wake us.
                floorRetryArmed = true
                scheduleRetry(after: config.partialHoldsFloor, clearsFloorRetry: true)
            }
            return
        }
    }

    /// Whether a refused turn keeps its place. The arc's answer always waits for its moment, and the
    /// opening never does. A gated turn waits only while someone speaks; a wrap-up also waits while
    /// the check of the newest segment is out. Any other refusal will not clear, and a turn kept for
    /// it would block the turns behind it.
    private func waits(_ turn: Queued, for reason: QuietReason) -> Bool {
        switch turn.kind {
        case .disclosure, .earlyWindDown:
            return true
        case .opening:
            return false
        case .reflection, .question, .wrapUp, .aboutApp:
            switch reason {
            case .personSpeaking, .appSpeaking: return true
            case .gate: return turn.kind == .wrapUp && callSegment != nil && callSegment == newestSegment
            default: return false
            }
        }
    }

    /// `playing` is set before the await, so an event that arrives meanwhile offers nothing on top.
    /// A refused draft is requeued but not offered again at once: the voice would refuse it again
    /// until a resume, a pause's grace, a turn's end or the floor retry.
    private func hand(_ turn: Queued) async {
        handCount += 1
        let hand = handCount
        playing = turn; started = false; playingHand = hand
        lastUnstarted = nil
        let accepted = await speak(turn.draft)
        guard playingHand == hand, playing != nil else { return }
        if accepted {
            // A disclosure came while `speak` was out: its cut may have reached the voice before this turn did.
            if cutHand == hand { await cut() }
            return
        }
        playing = nil
        if cutHand == hand {
            cutHand = nil
            return
        }
        requeue(turn)
    }

    /// Offer again after `delay`, then judge afresh: the person may have spoken, or the session
    /// paused or ended, in the meantime. Then ask about a segment whose grace has passed.
    private func scheduleRetry(after delay: Duration, clearsFloorRetry: Bool = false) {
        let id = UUID()
        retries[id] = Task {
            await sleep(delay)
            if clearsFloorRetry { floorRetryArmed = false }
            await offerPending()
            askIfAwaiting()
            retries[id] = nil
        }
    }

    // MARK: The interviewer call

    /// Starts one call about the segment awaiting a reply, if the policy names one and no call is out.
    /// The policy and the context are read with no await between them, so the request is built for
    /// the segment the policy named. A context whose newest segment is another one (the repository
    /// is ahead of the loop, or the segment is left out of AI) is never sent.
    private func askIfAwaiting() {
        guard let service, call == nil, !ended, !suspended, playing == nil,
              let segment = policy.segmentAwaitingReply(at: now()) else { return }
        let requestedAt = now()
        let request: InterviewerRequest, sessionWords: [String]
        do {
            (request, sessionWords) = try context()
        } catch {
            observe(.interviewerCheck(segment, nil))
            log("[interviewer] 0 ms error: context: \(error)")
            return
        }
        guard request.newestSegment == segment else {
            log("[interviewer] skipped: the context's newest segment is not the one awaiting a reply")
            return
        }
        callSegment = segment
        call = Task {
            let result: Result<InterviewerReply, ExtractionError>
            do throws(ExtractionError) { result = .success(try await service.reply(to: request)) } catch { result = .failure(error) }
            await replied(result, about: segment, requestedAt: requestedAt, sessionWords: sessionWords)
        }
    }

    /// Spec rule 4 and "The model turn": the check goes to the policy first, so an unclean one closes
    /// the gate before anything is offered. A reply with an unclean check is never offered: the arc's
    /// fixed text is the only answer to a disclosure. Then the client checks; then the turn is
    /// offered with the time its call started, so speech since then drops it.
    private func replied(_ result: Result<InterviewerReply, ExtractionError>, about segment: SegmentID,
                         requestedAt: Duration, sessionWords: [String]) async {
        call = nil; callSegment = nil
        let ms = Int(((now() - requestedAt) / .milliseconds(1)).rounded())
        switch result {
        case .failure(let error):
            observe(.interviewerCheck(segment, nil))
            log("[interviewer] \(ms) ms error: \(error)")
        case .success(let reply):
            observe(.interviewerCheck(segment, reply.check))
            if reply.check.isClean {
                let checked = TurnChecks.validate(reply, sessionWords: sessionWords)
                log("[interviewer] \(ms) ms \(Self.describe(checked))")
                if !ended, let turn = Self.turn(for: checked, requestedAt: requestedAt) { enqueue(turn) }
            } else {
                log("[interviewer] \(ms) ms dropped: check not clean")
            }
        }
        await offerPending()
        // A newer segment that waited for this call.
        askIfAwaiting()
    }

    private static func turn(for checked: CheckedTurn, requestedAt: Duration) -> Queued? {
        switch checked {
        case .speak(let kind, let text):
            Queued(draft: TurnDraft(kind: kind, source: .model, text: text), requestedAt: requestedAt)
        case .aboutApp:
            Queued(draft: TurnDraft(kind: .aboutApp, source: .fixed, text: FixedTurns.aboutTheApp), requestedAt: requestedAt)
        case .none, .dropped:
            nil
        }
    }

    private static func describe(_ checked: CheckedTurn) -> String {
        switch checked {
        case .speak(let kind, _): kind.rawValue
        case .aboutApp: TurnKind.aboutApp.rawValue
        case .none: "none"
        case .dropped(let reason): "dropped: \(reason)"
        }
    }
}
