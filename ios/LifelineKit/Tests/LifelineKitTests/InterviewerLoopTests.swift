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

/// A value the loop's closures and the test share.
private final class Shared<Value: Sendable>: Sendable {
    private let value: Mutex<Value>
    init(_ value: Value) { self.value = Mutex(value) }
    var current: Value { value.withLock { $0 } }
    func update(_ change: (inout Value) -> Void) { value.withLock { change(&$0) } }
}

/// One loop with a manual clock, a manual sleep and a `speak` that records drafts.
/// It plays the voice session's part: `finishTurn` reports the newest draft's playback.
private struct Harness {
    let clock = Shared<Duration>(.zero)
    let spokenDrafts = Shared<[TurnDraft]>([])
    let sleeper = ManualSleeper()
    let loop: InterviewerLoop

    init(kind: SessionKind = .settleIn) {
        let clock = clock, spokenDrafts = spokenDrafts, sleeper = sleeper
        loop = InterviewerLoop(kind: kind, config: .default,
                               speak: { draft in spokenDrafts.update { $0.append(draft) } },
                               now: { clock.current },
                               sleep: { await sleeper.sleep($0) })
    }

    var spoken: [TurnDraft] { spokenDrafts.current }
    var spokenKinds: [TurnKind] { spoken.map(\.kind) }

    func at(_ seconds: Double) { clock.update { $0 = .milliseconds(Int((seconds * 1000).rounded())) } }

    /// The voice session starts the turn and plays it to its end.
    func finishTurn() async {
        let id = InterviewerTurnID()
        await loop.voice(.turnStarted(id, atMs: 0))
        await loop.voice(.turnEnded(id, atMs: 0, interrupted: false))
    }

    /// The reply grace after a pause passes: wake the loop's sleep and wait for its retry.
    func gracePasses(expecting count: Int = 1) async {
        await sleeper.wakeAll(expecting: count)
        await loop.retriesSettled()
    }
}

private let opening = "Tell me about a kitchen you remember."

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

@Test func thePlannedLengthWrapUpIsNotSpokenYet() async {
    let h = Harness()
    h.at(1800); await h.loop.arc(.offerWrapUp(.plannedLength), stage: .windDown)
    h.at(1801); await h.loop.voice(.userPaused(afterMs: 1_801_000))
    h.at(1803); await h.gracePasses()
    #expect(h.spoken.isEmpty, "the wrap-up waits for the interviewer's check, in a later task")
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

@Test func aDraftDroppedDuringAPauseIsSpokenAfterResume() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    await h.loop.voice(.paused)
    #expect(h.spoken.count == 1, "handed out, but the session never started it")
    h.at(40); await h.loop.voice(.resumed)
    let past = try disclosureText(.past)
    #expect(h.spoken.map(\.text) == [past, past])
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .disclosure, .earlyWindDown])
}

@Test func nothingIsOfferedWhilePaused() async throws {
    let h = Harness()
    await h.loop.voice(.paused)
    await h.loop.captureStarted(opening: opening)
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    h.at(11); await h.loop.voice(.userPaused(afterMs: 11_000))
    h.at(13); await h.gracePasses()
    await h.loop.voice(.turnEnded(InterviewerTurnID(), atMs: 0, interrupted: true))
    #expect(h.spoken.isEmpty)
    h.at(20); await h.loop.voice(.resumed)
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown], "the opening is now or never")
}

@Test func aTurnCutAfterItStartedIsNotRespoken() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    let cut = InterviewerTurnID()
    await h.loop.voice(.turnStarted(cut, atMs: 10_000))
    // The session reports the cut turn's end before the pause; the wind-down line it offers then is dropped.
    await h.loop.voice(.turnEnded(cut, atMs: 11_000, interrupted: true))
    await h.loop.voice(.paused)
    h.at(30); await h.loop.voice(.resumed)
    await h.finishTurn()
    #expect(h.spokenKinds == [.disclosure, .earlyWindDown, .earlyWindDown])
    #expect(h.spoken.filter { $0.kind == .disclosure }.count == 1)
}

@Test func anInterruptionBehavesLikeAPause() async throws {
    let h = Harness()
    h.at(10); await h.loop.arc(.showDisclosureCard(.present), stage: .windDown)
    await h.loop.voice(.interrupted)
    h.at(12); await h.loop.voice(.userPaused(afterMs: 12_000))
    h.at(14); await h.gracePasses()
    #expect(h.spoken.count == 1, "nothing more while interrupted")
    h.at(30); await h.loop.voice(.resumed)
    let present = try disclosureText(.present)
    #expect(h.spoken.map(\.text) == [present, present])
}

@Test func aDroppedOpeningDoesNotBlockTheDisclosure() async throws {
    let h = Harness()
    await h.loop.captureStarted(opening: opening)
    await h.loop.voice(.paused)
    h.at(10); await h.loop.arc(.showDisclosureCard(.past), stage: .windDown)
    h.at(20); await h.loop.voice(.resumed)
    #expect(h.spokenKinds == [.opening, .disclosure])
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
