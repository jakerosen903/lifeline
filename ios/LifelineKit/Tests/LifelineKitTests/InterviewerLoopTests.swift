import Foundation
import Synchronization
import Testing
@testable import LifelineKit

/// A `sleep` the test wakes by hand. It records each requested duration.
private actor ManualSleeper {
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [Duration] = []

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { continuation in
            requested.append(duration)
            sleepers.append(continuation)
            watchers.forEach { $0.resume() }
            watchers = []
        }
    }

    /// Waits until `count` sleepers are asleep, then wakes them all.
    func wakeAll(expecting count: Int = 1) async {
        while sleepers.count < count {
            await withCheckedContinuation { watchers.append($0) }
        }
        sleepers.forEach { $0.resume() }
        sleepers = []
    }
}

/// An interviewer the test answers. Replies given at init are returned at once, in order; once they are
/// used up, each call waits for `answer`.
private actor TestInterviewer: InterviewerService {
    private var replies: [Result<InterviewerReply, ExtractionError>]
    private var waiting: [CheckedContinuation<Result<InterviewerReply, ExtractionError>, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [InterviewerRequest] = []

    init(_ replies: [Result<InterviewerReply, ExtractionError>] = []) { self.replies = replies }

    func reply(to request: InterviewerRequest) async throws(ExtractionError) -> InterviewerReply {
        requests.append(request)
        if !replies.isEmpty { return try replies.removeFirst().get() }
        let result = await withCheckedContinuation { continuation in
            waiting.append(continuation)
            watchers.forEach { $0.resume() }
            watchers = []
        }
        return try result.get()
    }

    /// Waits for a call to be out, then answers it.
    func answer(_ result: Result<InterviewerReply, ExtractionError>) async {
        while waiting.isEmpty {
            await withCheckedContinuation { watchers.append($0) }
        }
        waiting.removeFirst().resume(returning: result)
    }

    /// The newest segment's text of each request, in call order.
    var askedAbout: [String?] { requests.map(\.segments.first) }
}

/// A value the loop's closures and the test share.
private final class Shared<Value: Sendable>: Sendable {
    private let value: Mutex<Value>
    init(_ value: Value) { self.value = Mutex(value) }
    var current: Value { value.withLock { $0 } }
    func update(_ change: (inout Value) -> Void) { value.withLock { change(&$0) } }
}

/// One loop with a manual clock, a manual sleep and a `speak` that records the drafts it accepts.
/// It plays the voice session's part: `finishTurn` reports the newest draft's playback, and
/// `refuses` makes `speak` answer as a paused or interrupted session does. It plays the repository's
/// part too: `store` writes a segment the context reads, then tells the loop.
private struct Harness {
    let clock = Shared<Duration>(.zero)
    let spokenDrafts = Shared<[TurnDraft]>([])
    let refusedDrafts = Shared<[TurnDraft]>([])
    let refusing = Shared(false)
    let segments = Shared<[Segment]>([])
    let lines = Shared<[String]>([])
    let cutCount = Shared(0)
    let contextCount = Shared(0)
    let session = SessionID()
    let sleeper = ManualSleeper()
    let loop: InterviewerLoop

    init(kind: SessionKind = .settleIn, service: TestInterviewer? = nil) {
        let clock = clock, spokenDrafts = spokenDrafts, refusedDrafts = refusedDrafts, refusing = refusing, sleeper = sleeper
        let segments = segments, lines = lines, cutCount = cutCount, contextCount = contextCount, session = session
        loop = InterviewerLoop(kind: kind, config: .default,
                               service: service,
                               context: {
                                   contextCount.update { $0 += 1 }
                                   let stored = segments.current
                                   let request = InterviewerContext.build(session: session, segments: stored, excluded: [],
                                                                          opening: opening, stage: .open, turns: [])
                                   return (request, sessionWords: stored.map(\.text))
                               },
                               speak: { draft in
                                   if refusing.current { refusedDrafts.update { $0.append(draft) }; return false }
                                   spokenDrafts.update { $0.append(draft) }
                                   return true
                               },
                               cut: { cutCount.update { $0 += 1 } },
                               now: { clock.current },
                               sleep: { await sleeper.sleep($0) },
                               log: { line in lines.update { $0.append(line) } })
    }

    var spoken: [TurnDraft] { spokenDrafts.current }
    var spokenKinds: [TurnKind] { spoken.map(\.kind) }
    var refused: [TurnDraft] { refusedDrafts.current }
    var log: [String] { lines.current }
    var cuts: Int { cutCount.current }

    func refuses(_ refuses: Bool) { refusing.update { $0 = refuses } }

    func at(_ seconds: Double) { clock.update { $0 = .milliseconds(Int((seconds * 1000).rounded())) } }

    /// The voice session starts the turn and plays it to its end.
    func finishTurn() async {
        let id = InterviewerTurnID()
        await loop.voice(.turnStarted(id, atMs: 0))
        await loop.voice(.turnEnded(id, atMs: 0, interrupted: false))
    }

    /// The voice session cuts the newest draft before it started: an end with no start.
    func cutBeforeStart() async {
        await loop.voice(.turnEnded(InterviewerTurnID(), atMs: 0, interrupted: true))
    }

    /// Wakes the loop's sleeps and waits for their retries. A call they start is not waited for.
    func wakes(expecting count: Int = 1) async {
        await sleeper.wakeAll(expecting: count)
        await loop.retriesSettled()
    }

    /// The reply grace after a pause passes: wake the loop's sleep, wait for its retry and for any
    /// call it makes. Only for a service that answers at once.
    func gracePasses(expecting count: Int = 1) async {
        await wakes(expecting: count)
        await loop.callSettled()
    }

    /// The segment is in the repository, but the loop has not heard of it yet.
    @discardableResult
    func write(_ id: String, _ text: String) -> SegmentID {
        let segmentID = SegmentID(rawValue: id)
        let session = session
        segments.update {
            $0.append(Segment(id: segmentID, sessionID: session, index: $0.count, startMs: 0, endMs: 0, text: text, status: .pending))
        }
        return segmentID
    }

    @discardableResult
    func store(_ id: String, _ text: String) async -> SegmentID {
        let segmentID = write(id, text)
        await loop.segmentStored(segmentID)
        return segmentID
    }

    /// The person speaks from `start` and pauses at `pause`; the segment is stored at the pause.
    /// With a service, this leaves two sleeps due at `pause` + the grace: the pause's and the segment's.
    @discardableResult
    func story(_ id: String, _ text: String, from start: Double, pause: Double) async -> SegmentID {
        at(start); await loop.voice(.speechStarted(atMs: Int(start * 1000)))
        at(pause); await loop.voice(.userPaused(afterMs: Int(pause * 1000)))
        return await store(id, text)
    }
}

private let opening = "Tell me about a kitchen you remember."
private let bees = "we kept bees behind the old garage"

private func reflection(_ text: String, disclosure: DisclosureKind = .none) -> InterviewerReply {
    InterviewerReply(kind: .reflection, text: text, askedAboutApp: false, disclosure: disclosure, wantsToStop: false)
}

private let noTurn = InterviewerReply(kind: .none, text: nil, askedAboutApp: false, disclosure: .none, wantsToStop: false)
private let pastFlags = Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false)
private let cleanFlags = Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: false)

private func disclosureText(_ kind: DisclosureKind) throws -> String {
    try #require(try FixedResponses.spokenDisclosure(kind))
}

@Test func theOpeningIsSpokenOnce() async {
    let h = Harness()
    await h.loop.captureStarted(opening: opening)
    await h.loop.captureStarted(opening: opening)
    #expect(h.spoken == [TurnDraft(kind: .opening, source: .fixed, text: opening)])
    await h.finishTurn()
    await h.loop.captureStarted(opening: opening)
    #expect(h.spoken.count == 1, "a later call does not offer it again")
}

@Test func theOpeningIsSkippedIfThePersonAlreadySpoke() async {
    let h = Harness()
    h.at(0.2); await h.loop.voice(.speechStarted(atMs: 200))
    h.at(2.0); await h.loop.voice(.userPaused(afterMs: 2_000))
    h.at(2.1); await h.loop.captureStarted(opening: opening)
    #expect(h.spoken.isEmpty)
    h.at(3.5); await h.gracePasses()
    #expect(h.spoken.isEmpty, "a refused opening is dropped, not kept for later")
}

@Test func aDisclosureSpeaksTheKindsTextThenTheWindDownLine() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.spoken == [TurnDraft(kind: .disclosure, source: .fixed, text: try disclosureText(.past))])
    h.at(11); await h.loop.voice(.speechStarted(atMs: 11_000))
    h.at(12); await h.loop.voice(.userPaused(afterMs: 12_000))
    #expect(h.spoken.count == 1, "the wind-down waits for the disclosure text to be played")
    h.at(13); await h.finishTurn()
    #expect(h.spoken.last == TurnDraft(kind: .earlyWindDown, source: .fixed, text: FixedTurns.earlyWindDown))
    await h.finishTurn()
    h.at(20); await h.loop.arc(.offerWrapUp(.wantsToStop), stage: .windDown)
    h.at(22); await h.gracePasses()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown], "the wind-down line is spoken once")
}

@Test func presentAfterPastSpeaksThe988Line() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    await h.finishTurn(); await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown])
    #expect(!h.spoken[0].text.contains("988"))
    h.at(30); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    #expect(h.spoken.last == TurnDraft(kind: .disclosure, source: .fixed, text: try disclosureText(.present)))
    #expect(h.spoken.last?.text.contains("988") == true)
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown, .disclosure], "no second wind-down line")
}

@Test func presentBeforeThePastWindDownSpeaksThe988LineFirst() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    h.at(12); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    await h.finishTurn(); await h.finishTurn(); await h.finishTurn()
    #expect(h.spoken.map(\.text) == [try disclosureText(.past), try disclosureText(.present), FixedTurns.earlyWindDown])
}

@Test func aDisclosureWhileThePersonSpeaksWaitsForThePause() async throws {
    let h = Harness()
    h.at(5); await h.loop.voice(.speechStarted(atMs: 5_000))
    h.at(6); await h.loop.voice(.transcriptPartial("and then he"))
    h.at(7); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.spoken.isEmpty, "never over the person")
    h.at(8); await h.loop.voice(.userPaused(afterMs: 8_000))
    #expect(h.spoken.isEmpty, "a partial 2 s ago is gone, but the grace has not passed")
    h.at(9); await h.loop.voice(.speechStarted(atMs: 9_000))
    h.at(9.5); await h.gracePasses()
    #expect(h.spoken.isEmpty, "the person spoke again inside the grace")
    h.at(12); await h.loop.voice(.userPaused(afterMs: 12_000))
    h.at(13.5); await h.gracePasses()
    #expect(h.spoken == [TurnDraft(kind: .disclosure, source: .fixed, text: try disclosureText(.past))])
    #expect(await h.sleeper.requested == [ArcConfig.default.replyGrace, ArcConfig.default.replyGrace])
}

@Test func quickStoryWantsToStopSpeaksTheWindDownLine() async {
    let h = Harness(kind: .quick)
    await h.loop.captureStarted(opening: opening)
    await h.finishTurn()
    h.at(3); await h.loop.voice(.speechStarted(atMs: 3_000))
    h.at(9); await h.loop.voice(.userPaused(afterMs: 9_000))
    await h.loop.segmentStored(SegmentID(rawValue: "s1"))
    await h.loop.flags(Flags(disclosure: .none, wantsToStop: true, wantsToChangeSubject: false), segment: SegmentID(rawValue: "s1"))
    h.at(10); await h.loop.arc(.offerWrapUp(.wantsToStop), stage: .windDown)
    #expect(h.spoken.last == TurnDraft(kind: .earlyWindDown, source: .fixed, text: FixedTurns.earlyWindDown))
    #expect(h.spokenKinds == [.opening, .earlyWindDown])
}

@Test func aWrapUpWithNoCheckIsNotSpoken() async {
    let h = Harness(service: TestInterviewer())
    h.at(1800); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    h.at(1801); await h.loop.voice(.userPaused(afterMs: 1_801_000))
    h.at(1803); await h.gracePasses()
    #expect(h.spoken.isEmpty, "no segment was checked, and no check is out")
    #expect(h.log.contains("[interviewer] dropped a wrapUp turn: gate"))
}

@Test func quietStopsEverythingButTheDisclosure() async throws {
    let h = Harness()
    let states = Task { await h.loop.states.first { _ in true } }
    await h.loop.setQuiet(true)
    #expect(await states.value == InterviewerState(isQuiet: true))
    await h.loop.captureStarted(opening: opening)
    #expect(h.spoken.isEmpty, "quiet holds the opening")
    h.at(10); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    #expect(h.spoken.map(\.text) == [try disclosureText(.present)])
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown], "spec rule 3: the wind-down line answers the arc too")
}

@Test func theSessionEndingStopsEveryOffer() async {
    let h = Harness()
    h.at(5); await h.loop.voice(.speechStarted(atMs: 5_000))
    h.at(6); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    h.at(7); await h.loop.arc(.land, stage: .ended)
    h.at(8); await h.loop.voice(.userPaused(afterMs: 8_000))
    h.at(10); await h.gracePasses()
    await h.finishTurn()
    await h.loop.captureStarted(opening: opening)
    #expect(h.spoken.isEmpty)
}

@Test func keepGoingLeavesTheWindDownAfterADisclosure() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    await h.loop.keepGoing()
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown])
}

// MARK: Pauses and interruptions

@Test func aDraftCutBeforeItStartedIsSpokenAfterResume() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    // The session pauses before playback starts: the turn ends unstarted and waits at the front,
    // not offered at once (the paused session would refuse it). Then the pause is reported.
    await h.cutBeforeStart()
    await h.loop.voice(.paused)
    #expect(h.spoken.count == 1 && h.refused.isEmpty)
    h.at(40); await h.loop.voice(.resumed)
    let past = try disclosureText(.past)
    #expect(h.spoken.map(\.text) == [past, past])
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .disclosure, .earlyWindDown])
}

@Test func aResumeWhileStillInterruptedDoesNotLoseTheDisclosure() async throws {
    let h = Harness()
    await h.loop.voice(.paused)
    h.at(10); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    await h.loop.voice(.interrupted)
    // `resume()` ends the pause, but the interruption holds: the session refuses the turn.
    h.refuses(true)
    h.at(20); await h.loop.voice(.resumed)
    let present = try disclosureText(.present)
    #expect(h.refused.map(\.text) == [present] && h.spoken.isEmpty)
    h.at(21); await h.loop.voice(.userPaused(afterMs: 21_000))
    h.at(22.5); await h.gracePasses()
    #expect(h.refused.count == 2, "the refused draft stays at the front")
    h.refuses(false)
    h.at(30); await h.loop.voice(.resumed)
    #expect(h.spoken.map(\.text) == [present])
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown])
}

@Test func nothingIsOfferedWhilePaused() async throws {
    let h = Harness()
    await h.loop.voice(.paused)
    await h.loop.captureStarted(opening: opening)
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    h.at(11); await h.loop.voice(.userPaused(afterMs: 11_000))
    h.at(13); await h.gracePasses()
    await h.loop.voice(.turnEnded(InterviewerTurnID(), atMs: 0, interrupted: true))
    #expect(h.spoken.isEmpty && h.refused.isEmpty)
    h.at(20); await h.loop.voice(.resumed)
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown], "the opening is now or never")
}

@Test func aTurnCutAfterItStartedIsNotRespoken() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    let cut = InterviewerTurnID()
    await h.loop.voice(.turnStarted(cut, atMs: 10_000))
    // The session is pausing: it reports the cut turn's end, then refuses the wind-down line it is offered.
    h.refuses(true)
    await h.loop.voice(.turnEnded(cut, atMs: 11_000, interrupted: true))
    await h.loop.voice(.paused)
    #expect(h.refused.map(\.kind) == [.earlyWindDown])
    h.refuses(false)
    h.at(30); await h.loop.voice(.resumed)
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown], "the cut disclosure text is not spoken again")
}

@Test func anInterruptionBehavesLikeAPause() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    h.refuses(true)   // an offer during the interruption would be refused and show up in `refused`
    await h.cutBeforeStart()
    await h.loop.voice(.interrupted)
    h.at(12); await h.loop.voice(.userPaused(afterMs: 12_000))
    h.at(14); await h.gracePasses()
    #expect(h.spoken.count == 1 && h.refused.isEmpty, "no offer after the unstarted end, nor while interrupted")
    h.refuses(false)
    h.at(30); await h.loop.voice(.resumed)
    let present = try disclosureText(.present)
    #expect(h.spoken.map(\.text) == [present, present])
}

@Test func anUnstartedEndDoesNotReofferAtOnce() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    // The voice failed before any audio: the turn ends with no start, and nothing is paused.
    await h.cutBeforeStart()
    #expect(h.spoken.count == 1 && h.refused.isEmpty, "a failing voice must not be fed the same draft in a loop")
    h.at(11); await h.loop.voice(.userPaused(afterMs: 11_000))
    h.at(12.5); await h.gracePasses()
    let past = try disclosureText(.past)
    #expect(h.spoken.map(\.text) == [past, past], "the next pause's grace offers it again, from the front")
}

@Test func aDraftThatNeverStartsIsDroppedAfterThreeTries() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    for attempt in 1...3 {
        await h.cutBeforeStart()
        let at = 10.0 + Double(attempt) * 2
        h.at(at); await h.loop.voice(.userPaused(afterMs: Int(at * 1000)))
        h.at(at + 1.5); await h.gracePasses()
    }
    let past = try disclosureText(.past)
    #expect(h.spoken.map(\.text) == [past, past, past, FixedTurns.earlyWindDown],
            "after the third unstarted end the draft is dropped and the turn behind it goes next")
}

@Test func pausesDoNotCountTowardTheDrop() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    for attempt in 1...3 {
        // The person pauses before the audio starts: the session ends the turn, then reports the pause.
        await h.cutBeforeStart()
        await h.loop.voice(.paused)
        h.at(10 + Double(attempt) * 10); await h.loop.voice(.resumed)
    }
    let past = try disclosureText(.past)
    #expect(h.spoken.map(\.text) == [past, past, past, past], "three pause cuts are not voice failures")
}

@Test func aDroppedOpeningDoesNotBlockTheDisclosure() async throws {
    let h = Harness()
    await h.loop.captureStarted(opening: opening)
    await h.cutBeforeStart()
    await h.loop.voice(.paused)
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    h.at(20); await h.loop.voice(.resumed)
    #expect(h.spokenKinds == [.opening, .disclosure] && h.refused.isEmpty)
}

@Test func aRefusedOpeningIsNotRequeued() async throws {
    let h = Harness()
    h.refuses(true)
    await h.loop.captureStarted(opening: opening)
    h.refuses(false)
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.refused.map(\.kind) == [.opening])
    #expect(h.spokenKinds == [.disclosure])
}

@Test func aPartialAfterThePauseDoesNotStrandTheDisclosure() async throws {
    let h = Harness()
    h.at(5); await h.loop.voice(.speechStarted(atMs: 5_000))
    h.at(6); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    h.at(8); await h.loop.voice(.userPaused(afterMs: 8_000))
    h.at(9); await h.loop.voice(.transcriptPartial("my brother"))
    h.at(9.5); await h.gracePasses()
    #expect(h.spoken.isEmpty, "the late partial still holds the floor")
    h.at(10.5); await h.gracePasses()
    #expect(h.spokenKinds == [.disclosure])
    #expect(await h.sleeper.requested == [ArcConfig.default.replyGrace, ArcConfig.default.partialHoldsFloor])
}

@Test func aPastAfterPresentSpeaksNothingMore() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    await h.finishTurn(); await h.finishTurn()
    h.at(20); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.spoken.map(\.text) == [try disclosureText(.present), FixedTurns.earlyWindDown])
}

// MARK: Reflections behind the gate

@Test func aReflectionFollowsAClosedSegmentAfterTheGrace() async {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage."))])
    let h = Harness(service: service)
    await h.loop.captureStarted(opening: opening)
    await h.finishTurn()
    await h.story("s1", bees, from: 2, pause: 8)
    #expect(await service.requests.isEmpty, "the grace has not passed")
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(await service.askedAbout == [bees])
    #expect(h.spoken.last == TurnDraft(kind: .reflection, source: .model, text: "Bees behind the old garage."))
    #expect(h.log == ["[interviewer] 0 ms reflection"])
}

@Test func speechDuringTheCallDropsTheReply() async {
    let service = TestInterviewer()
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.wakes(expecting: 2)
    // A short sound while the call is out: speech starts and pauses, and no segment is stored.
    h.at(10); await h.loop.voice(.speechStarted(atMs: 10_000))
    h.at(10.4); await h.loop.voice(.userPaused(afterMs: 10_400))
    h.at(10.8); await service.answer(.success(reflection("Bees behind the old garage.")))
    await h.loop.callSettled()
    #expect(h.spoken.isEmpty)
    #expect(h.log == ["[interviewer] 1300 ms reflection", "[interviewer] dropped a reflection turn: stale"])
    h.at(12); await h.gracePasses()
    #expect(h.spoken.isEmpty, "a dropped reply does not come back")
}

@Test func aFailedCallIsSilent() async {
    let service = TestInterviewer([.failure(.network("offline")), .success(reflection("A blue door."))])
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(h.spoken.isEmpty)
    #expect(h.log.first?.hasPrefix("[interviewer] 0 ms error: ") == true)
    await h.story("s2", "the house had a blue door", from: 12, pause: 15)
    h.at(16.5); await h.gracePasses(expecting: 2)
    #expect(h.spoken.isEmpty, "a missing check is not clean: the gate waits for s1's flags")
    h.at(17); await h.loop.flags(Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: false), segment: SegmentID(rawValue: "s1"))
    #expect(h.spoken == [TurnDraft(kind: .reflection, source: .model, text: "A blue door.")])
}

@Test func noKeyMeansNoCallsAndNoSpokenWrapUp() async throws {
    let h = Harness(service: nil)
    await h.loop.captureStarted(opening: opening)
    await h.finishTurn()
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses()
    h.at(1800); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    h.at(1801); await h.loop.voice(.userPaused(afterMs: 1_801_000))
    h.at(1803); await h.gracePasses()
    #expect(h.spokenKinds == [.opening])
    #expect(h.contextCount.current == 0 && h.log.isEmpty)
    h.at(1810); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    await h.finishTurn()
    #expect(h.spokenKinds == [.opening, .disclosure, .earlyWindDown], "the arc's answer still plays")
}

@Test func theWrapUpWaitsForACleanCheck() async {
    let service = TestInterviewer()
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.wakes(expecting: 2)
    h.at(10); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    #expect(h.spoken.isEmpty, "the check of the newest segment is still out")
    h.at(10.5); await service.answer(.success(noTurn))
    await h.loop.callSettled()
    #expect(h.spoken == [TurnDraft(kind: .wrapUp, source: .fixed, text: FixedTurns.wrapUp)])
}

@Test func theWrapUpIsNotSpokenAfterAnUncleanCheck() async {
    let service = TestInterviewer()
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.wakes(expecting: 2)
    h.at(10); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    h.at(10.5); await service.answer(.success(InterviewerReply(kind: .none, text: nil, askedAboutApp: false, disclosure: .none, wantsToStop: true)))
    await h.loop.callSettled()
    #expect(h.spoken.isEmpty)
}

@Test func keepGoingWithdrawsAWaitingWrapUp() async {
    let service = TestInterviewer()
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.wakes(expecting: 2)
    h.at(10); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    await h.loop.keepGoing()
    h.at(10.5); await service.answer(.success(noTurn))
    await h.loop.callSettled()
    #expect(h.spoken.isEmpty)
}

@Test func aboutTheAppSpeaksTheFixedLine() async {
    let reply = InterviewerReply(kind: .reflection, text: "I record things.", askedAboutApp: true, disclosure: .none, wantsToStop: false)
    let service = TestInterviewer([.success(reply)])
    let h = Harness(service: service)
    await h.story("s1", "what is this app anyway", from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(h.spoken == [TurnDraft(kind: .aboutApp, source: .fixed, text: FixedTurns.aboutTheApp)], "never the model's text")
    #expect(h.log == ["[interviewer] 0 ms aboutApp"])
}

@Test func aTurnThatFailsACheckIsDropped() async {
    let service = TestInterviewer([.success(reflection("The bees and Maya."))])
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(h.spoken.isEmpty)
    #expect(h.log == ["[interviewer] 0 ms dropped: not said: maya"])
}

@Test func noCallInAQuickStory() async {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage."))])
    let h = Harness(kind: .quick, service: service)
    await h.loop.captureStarted(opening: opening)
    await h.finishTurn()
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(await service.requests.isEmpty)
    #expect(h.spokenKinds == [.opening])
}

@Test func noCallWhenQuiet() async {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage."))])
    let h = Harness(service: service)
    await h.loop.setQuiet(true)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(await service.requests.isEmpty)
    #expect(h.spoken.isEmpty)
}

@Test func aDisclosureSegmentWithASlowFlagGetsNoModelTurn() async throws {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage.", disclosure: .past))])
    let h = Harness(service: service)
    await h.loop.captureStarted(opening: opening)
    await h.finishTurn()
    let s1 = await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(h.spokenKinds == [.opening], "the check says past: no model turn, before any flag")
    #expect(h.log == ["[interviewer] 0 ms dropped: check not clean"])
    h.at(14.5); await h.loop.flags(pastFlags, segment: s1)
    await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    await h.finishTurn(); await h.finishTurn()
    #expect(h.spoken.map(\.text) == [opening, try disclosureText(.past), FixedTurns.earlyWindDown])
    #expect(!h.spoken.contains { $0.source == .model })
}

@Test func twoSegmentsInsideTheGraceGetOneReflection() async {
    let service = TestInterviewer([.success(reflection("A blue door.")), .success(reflection("Bees behind the old garage."))])
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    await h.story("s2", "the house had a blue door", from: 8.5, pause: 9)
    // The sleeps of the first pause and segment are due at 9.5, those of the second at 10.5.
    h.at(10.5); await h.gracePasses(expecting: 4)
    #expect(await service.askedAbout == ["the house had a blue door"])
    #expect(h.spoken == [TurnDraft(kind: .reflection, source: .model, text: "A blue door.")])
}

@Test func aNewerSegmentWaitsForTheCallInFlight() async {
    let service = TestInterviewer()
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.wakes(expecting: 2)
    await h.story("s2", "the house had a blue door", from: 9.6, pause: 10)
    h.at(11.5); await h.wakes(expecting: 2)
    #expect(await service.requests.count == 1, "one call at a time")
    h.at(11.6); await service.answer(.success(reflection("Bees behind the old garage.")))
    h.at(11.8); await service.answer(.success(reflection("A blue door.")))
    await h.loop.callSettled()
    #expect(await service.askedAbout == [bees, "the house had a blue door"])
    #expect(h.spoken == [TurnDraft(kind: .reflection, source: .model, text: "A blue door.")],
            "the reply about the older segment is held by the gate")
}

@Test func aSegmentStoredAfterTheGraceStillGetsAReflection() async {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage."))])
    let h = Harness(service: service)
    h.at(2); await h.loop.voice(.speechStarted(atMs: 2_000))
    h.at(8); await h.loop.voice(.userPaused(afterMs: 8_000))
    h.at(9.5); await h.gracePasses()
    #expect(await service.requests.isEmpty, "no segment yet")
    h.at(10); await h.store("s1", bees)
    await h.loop.callSettled()
    #expect(await service.askedAbout == [bees])
    #expect(h.spokenKinds == [.reflection])
}

@Test func aContextAheadOfTheLoopIsNotSent() async {
    let service = TestInterviewer([.success(reflection("A blue door."))])
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.write("s2", "the house had a blue door")
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(await service.requests.isEmpty, "the context's newest segment is not the one awaiting a reply")
    #expect(h.log.filter { $0.contains("skipped") }.count == 1, "both wakes, one log line")
    h.at(9.6); await h.loop.segmentStored(SegmentID(rawValue: "s2"))
    await h.loop.callSettled()
    #expect(await service.askedAbout == ["the house had a blue door"])
    #expect(h.spoken.isEmpty, "the skipped segment holds the gate until its flags arrive")
    h.at(10); await h.loop.flags(cleanFlags, segment: SegmentID(rawValue: "s1"))
    #expect(h.spokenKinds == [.reflection])
}

@Test func aDisclosureCutsAPlayingReflection() async throws {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage."))])
    let h = Harness(service: service)
    let s1 = await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    let playing = InterviewerTurnID()
    await h.loop.voice(.turnStarted(playing, atMs: 9_600))
    h.at(10); await h.loop.flags(pastFlags, segment: s1)
    await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.cuts == 1)
    #expect(h.spokenKinds == [.reflection], "the disclosure waits for the cut turn's end")
    await h.loop.voice(.turnEnded(playing, atMs: 10_100, interrupted: true))
    await h.finishTurn(); await h.finishTurn()
    #expect(h.spoken.map(\.text) == ["Bees behind the old garage.", try disclosureText(.past), FixedTurns.earlyWindDown])
}

@Test func aCutDraftThatNeverStartedIsNotRespoken() async throws {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage."))])
    let h = Harness(service: service)
    let s1 = await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    h.at(9.6); await h.loop.flags(pastFlags, segment: s1)
    await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.cuts == 1)
    await h.cutBeforeStart()
    #expect(h.spokenKinds == [.reflection, .disclosure], "the disclosure is offered at once after the cut")
    await h.finishTurn(); await h.finishTurn()
    #expect(h.spokenKinds == [.reflection, .disclosure, .earlyWindDown])
}

@Test func aDisclosureDoesNotCutAPlayingDisclosureText() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    await h.loop.voice(.turnStarted(InterviewerTurnID(), atMs: 10_000))
    h.at(11); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    #expect(h.cuts == 0, "the past text plays out; the 988 text follows it")
}

@Test func aWaitingWrapUpDoesNotBlockADisclosure() async throws {
    let service = TestInterviewer()
    let h = Harness(service: service)
    let s1 = await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.wakes(expecting: 2)
    h.at(10); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    #expect(h.spoken.isEmpty, "the wrap-up waits for the check that is out")
    h.at(11); await h.loop.flags(pastFlags, segment: s1)
    await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.spoken.map(\.text) == [try disclosureText(.past)])
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown], "the wind-down line goes ahead of the wrap-up too")
    await h.finishTurn()
    h.at(12); await service.answer(.success(noTurn))
    await h.loop.callSettled()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown], "after a heavy flag the wrap-up is dropped")
}

@Test func theSessionEndingDropsAReplyInFlight() async {
    let service = TestInterviewer()
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.wakes(expecting: 2)
    h.at(10); await h.loop.arc(.land, stage: .ended)
    await service.answer(.success(reflection("Bees behind the old garage.")))
    await h.loop.callSettled()
    #expect(h.spoken.isEmpty)
}

// MARK: Fix round 1: failed checks, the wind-down cut, check-only calls

@Test func aFailedCheckHoldsLaterReflectionsUntilItsFlagsArrive() async {
    let service = TestInterviewer([.failure(.network("offline")), .success(reflection("A blue door."))])
    let h = Harness(service: service)
    let s1 = await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    await h.story("s2", "the house had a blue door", from: 10, pause: 12)
    h.at(13.5); await h.gracePasses(expecting: 2)
    #expect(await service.requests.count == 2)
    #expect(h.spoken.isEmpty, "s2's check is clean, but s1 has neither a check nor flags")
    h.at(14); await h.loop.flags(cleanFlags, segment: s1)
    #expect(h.spoken == [TurnDraft(kind: .reflection, source: .model, text: "A blue door.")])
}

@Test func heavyFlagsForAFailedCheckSilenceLaterReflections() async {
    let service = TestInterviewer([.failure(.network("offline")), .success(reflection("A blue door."))])
    let h = Harness(service: service)
    let s1 = await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    await h.story("s2", "the house had a blue door", from: 10, pause: 12)
    h.at(13.5); await h.gracePasses(expecting: 2)
    h.at(14); await h.loop.flags(pastFlags, segment: s1)
    h.at(16); await h.loop.voice(.userPaused(afterMs: 16_000))
    h.at(17.5); await h.gracePasses()
    #expect(h.spoken.isEmpty)
}

@Test func aDisclosureCutsAPlayingWindDownLineAndSaysItAfter() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.offerWrapUp(.wantsToStop), stage: .windDown)
    let playing = InterviewerTurnID()
    await h.loop.voice(.turnStarted(playing, atMs: 10_000))
    h.at(11); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    #expect(h.cuts == 1)
    await h.loop.voice(.turnEnded(playing, atMs: 11_100, interrupted: true))
    await h.finishTurn(); await h.finishTurn()
    #expect(h.spoken.map(\.text) == [FixedTurns.earlyWindDown, try disclosureText(.past), FixedTurns.earlyWindDown])
}

/// s1 closes at 8; the planned length comes at 9, inside the grace.
private func wrapUpInsideTheGrace(_ h: Harness) async {
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
}

@Test func aWrapUpInWindDownAsksForACheckAfterTheGrace() async {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage."))])
    let h = Harness(service: service)
    await wrapUpInsideTheGrace(h)
    #expect(h.spoken.isEmpty)
    #expect(await service.requests.isEmpty, "the grace has not passed")
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(await service.askedAbout == [bees])
    #expect(h.spoken == [TurnDraft(kind: .wrapUp, source: .fixed, text: FixedTurns.wrapUp)], "the reply's words are never spoken")
    #expect(h.log == ["[interviewer] 0 ms check only"])
}

@Test func aCheckOnlyReplyNeverSpeaksTheAboutAppLine() async {
    let reply = InterviewerReply(kind: .none, text: nil, askedAboutApp: true, disclosure: .none, wantsToStop: false)
    let h = Harness(service: TestInterviewer([.success(reply)]))
    await wrapUpInsideTheGrace(h)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(h.spokenKinds == [.wrapUp])
}

@Test func anUncleanCheckOnlyCallDropsTheWrapUp() async {
    let h = Harness(service: TestInterviewer([.success(reflection("Bees.", disclosure: .past))]))
    await wrapUpInsideTheGrace(h)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(h.spoken.isEmpty)
    #expect(h.log == ["[interviewer] 0 ms check only", "[interviewer] dropped a wrapUp turn: gate"])
}

@Test func aFailedCheckOnlyCallDropsTheWrapUp() async {
    let h = Harness(service: TestInterviewer([.failure(.network("offline"))]))
    await wrapUpInsideTheGrace(h)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(h.spoken.isEmpty)
    #expect(h.log.last == "[interviewer] dropped a wrapUp turn: gate")
}

@Test func noCheckOnlyCallWithoutAWaitingWrapUp() async {
    let service = TestInterviewer([.success(noTurn)])
    let h = Harness(service: service)
    h.at(1); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    #expect(h.log == ["[interviewer] dropped a wrapUp turn: gate"], "no segment to check")
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    #expect(await service.requests.isEmpty)
}

@Test func noCheckOnlyCallWhenQuietOrInAQuickStory() async {
    let quickService = TestInterviewer([.success(noTurn)])
    let quick = Harness(kind: .quick, service: quickService)
    await wrapUpInsideTheGrace(quick)
    quick.at(9.5); await quick.gracePasses(expecting: 2)
    #expect(await quickService.requests.isEmpty)
    #expect(quick.spoken.isEmpty)

    let quietService = TestInterviewer([.success(noTurn)])
    let quiet = Harness(service: quietService)
    await quiet.loop.setQuiet(true)
    await wrapUpInsideTheGrace(quiet)
    quiet.at(9.5); await quiet.gracePasses(expecting: 2)
    #expect(await quietService.requests.isEmpty)
    #expect(quiet.spoken.isEmpty)
}

@Test func aCheckedSegmentGetsNoSecondCall() async {
    let service = TestInterviewer([.success(noTurn), .success(noTurn)])
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    h.at(10); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    h.at(10.5); await h.loop.voice(.userPaused(afterMs: 10_500))
    h.at(12); await h.gracePasses()
    #expect(await service.requests.count == 1)
    #expect(h.spokenKinds == [.wrapUp])
}

@Test func aWrapUpAfterAReflectionWaitsForTheNextSegmentAndItsCheck() async {
    let service = TestInterviewer([.success(reflection("Bees behind the old garage.")), .success(reflection("A blue door."))])
    let h = Harness(service: service)
    await h.story("s1", bees, from: 2, pause: 8)
    h.at(9.5); await h.gracePasses(expecting: 2)
    await h.finishTurn()
    h.at(10); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    #expect(h.spokenKinds == [.reflection], "rule 6: no turn without a segment since")
    await h.story("s2", "the house had a blue door", from: 11, pause: 14)
    h.at(15.5); await h.gracePasses(expecting: 2)
    #expect(await service.askedAbout == [bees, "the house had a blue door"])
    #expect(h.spoken.map(\.text) == ["Bees behind the old garage.", FixedTurns.wrapUp])
}
