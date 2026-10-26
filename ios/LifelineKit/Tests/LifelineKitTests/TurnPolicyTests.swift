import Testing
@testable import LifelineKit

/// Spec "Turn policy", rules 1 to 10, and "Session kinds". Times are seconds since the session started.
struct TurnPolicyTests {
    private let clean = SafetyCheck(disclosure: .none, wantsToStop: false)
    private let pastDisclosure = SafetyCheck(disclosure: .past, wantsToStop: false)
    private let wantsToStop = SafetyCheck(disclosure: .none, wantsToStop: true)
    private let first = SegmentID(rawValue: "s1"), second = SegmentID(rawValue: "s2")
    private let third = SegmentID(rawValue: "s3"), fourth = SegmentID(rawValue: "s4")

    private func t(_ seconds: Double) -> Duration { .milliseconds(Int((seconds * 1000).rounded())) }

    /// Model kinds come from the model; every other kind is the app's own copy.
    private func offer(_ kind: TurnKind, requestedAt: Double? = nil) -> TurnOffer {
        let source: TurnSource = kind == .reflection || kind == .question ? .model : .fixed
        return TurnOffer(kind: kind, source: source, text: "Invented words.", requestedAt: requestedAt.map(t))
    }

    private func policy(_ kind: SessionKind = .settleIn) -> TurnPolicy { TurnPolicy(kind: kind, config: .default) }

    /// The person speaks for 3 s from `start`; the segment is stored at the pause. When `checked`, the
    /// interviewer's check arrives 0.5 s later; a nil `check` is a failed call.
    private func tell(_ p: inout TurnPolicy, _ segment: SegmentID, at start: Double, check: SafetyCheck? = nil,
                      checked: Bool = true) {
        p.observe(.speechStarted, at: t(start))
        p.observe(.partial, at: t(start + 1))
        p.observe(.userPaused, at: t(start + 3))
        p.observe(.segmentStored(segment), at: t(start + 3))
        guard checked else { return }
        p.observe(.interviewerCheck(segment, check), at: t(start + 3.5))
    }

    private func tellClean(_ p: inout TurnPolicy, _ segment: SegmentID, at start: Double) {
        tell(&p, segment, at: start, check: clean)
    }

    private func speak(_ p: inout TurnPolicy, _ kind: TurnKind, at start: Double) {
        p.observe(.turnStarted(kind), at: t(start))
        p.observe(.turnEnded, at: t(start + 1))
    }

    // MARK: Rule 1

    @Test func quietWhilePersonSpeaks() {
        var p = policy()
        p.observe(.speechStarted, at: t(1))
        #expect(p.decide(offer(.disclosure), at: t(5)) == .stayQuiet(.personSpeaking), "no pause after the start")
        p.observe(.userPaused, at: t(6))
        p.observe(.partial, at: t(6.2))
        #expect(p.decide(offer(.disclosure), at: t(7.0)) == .stayQuiet(.personSpeaking), "a partial 0.8 s ago")
        #expect(p.decide(offer(.disclosure), at: t(7.4)) == .speak, "a partial 1.2 s ago")
    }

    @Test func quietWhileTheAppSpeaks() {
        var p = policy()
        p.observe(.turnStarted(.opening), at: t(0))
        #expect(p.decide(offer(.disclosure), at: t(1)) == .stayQuiet(.appSpeaking))
        p.observe(.turnEnded, at: t(2))
        #expect(p.decide(offer(.disclosure), at: t(2.1)) == .speak)
    }

    // MARK: Rule 2

    @Test func heavyFlagsEndModelTurns() {
        var p = policy()
        tellClean(&p, first, at: 0)
        p.observe(.extractorFlags(first, Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false)), at: t(5))
        #expect(p.decide(offer(.reflection), at: t(6)) == .stayQuiet(.heavy))
        tellClean(&p, second, at: 10)
        p.observe(.extractorFlags(second, .none), at: t(14))
        #expect(p.decide(offer(.reflection), at: t(15)) == .stayQuiet(.heavy), "for the rest of the session")
        #expect(p.decide(offer(.wrapUp), at: t(15)) == .stayQuiet(.gate))
        #expect(p.decide(offer(.disclosure), at: t(15)) == .speak, "fixed turns are still spoken")

        var stop = policy()
        tellClean(&stop, first, at: 0)
        stop.observe(.extractorFlags(first, Flags(disclosure: .none, wantsToStop: true, wantsToChangeSubject: false)), at: t(5))
        #expect(stop.decide(offer(.question), at: t(6)) == .stayQuiet(.heavy), "wants to stop is a heavy moment too")
    }

    // MARK: Rule 3

    @Test func quietAllowsOnlyDisclosureAndWindDown() {
        var p = policy()
        p.observe(.quiet(true), at: t(0))
        #expect(p.decide(offer(.opening), at: t(0)) == .stayQuiet(.quiet))
        tellClean(&p, first, at: 1)
        for kind in [TurnKind.reflection, .question, .wrapUp, .aboutApp] {
            #expect(p.decide(offer(kind), at: t(6)) == .stayQuiet(.quiet), "\(kind)")
        }
        #expect(p.decide(offer(.disclosure), at: t(6)) == .speak)
        #expect(p.decide(offer(.earlyWindDown), at: t(6)) == .speak)
        p.observe(.quiet(false), at: t(7))
        #expect(p.decide(offer(.reflection), at: t(7)) == .speak, "\"Ask me again\" brings turns back")
    }

    // MARK: Rule 4, the gate

    @Test func noTurnBeforeTheCheckReturns() {
        var p = policy()
        tell(&p, first, at: 0, checked: false)
        for kind in [TurnKind.reflection, .question, .wrapUp, .aboutApp] {
            #expect(p.decide(offer(kind), at: t(5)) == .stayQuiet(.gate), "\(kind)")
        }
        p.observe(.interviewerCheck(first, clean), at: t(6))
        #expect(p.decide(offer(.reflection), at: t(6)) == .speak)
    }

    @Test func noGatedTurnBeforeAnySegment() {
        let p = policy()
        #expect(p.decide(offer(.wrapUp), at: t(5)) == .stayQuiet(.gate))
        #expect(p.decide(offer(.opening), at: t(0)) == .speak, "the opening is not gated")
    }

    @Test func aFailedCheckIsSilent() {
        var p = policy()
        tell(&p, first, at: 0, check: nil)
        #expect(p.decide(offer(.reflection), at: t(5)) == .stayQuiet(.gate))
        #expect(p.decide(offer(.wrapUp), at: t(5)) == .stayQuiet(.gate))
        tellClean(&p, second, at: 10)
        #expect(p.decide(offer(.reflection), at: t(15)) == .stayQuiet(.gate), "a missing check is not clean until its flags arrive")
        p.observe(.extractorFlags(first, Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: false)), at: t(16))
        #expect(p.decide(offer(.reflection), at: t(17)) == .speak, "clean flags release it: no latch")
    }

    @Test func anUncleanCheckSilencesTheTurnAndLaterTurns() {
        var p = policy()
        tell(&p, first, at: 0, check: pastDisclosure)
        #expect(p.decide(offer(.reflection), at: t(5)) == .stayQuiet(.gate))
        #expect(p.decide(offer(.wrapUp), at: t(5)) == .stayQuiet(.gate))
        #expect(p.decide(offer(.disclosure), at: t(5)) == .speak, "the arc's answer is not gated")
        #expect(p.decide(offer(.earlyWindDown), at: t(5)) == .speak)
    }

    @Test func anUncleanCheckOnAnEarlierSegmentSilencesLaterTurns() {
        var p = policy()
        tell(&p, first, at: 0, check: wantsToStop)
        tellClean(&p, second, at: 10)
        p.observe(.extractorFlags(second, .none), at: t(14))
        for kind in [TurnKind.reflection, .question, .wrapUp, .aboutApp] {
            #expect(p.decide(offer(kind), at: t(15)) == .stayQuiet(.gate), "\(kind)")
        }

        var flagged = policy()
        tellClean(&flagged, first, at: 0)
        flagged.observe(.extractorFlags(first, Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false)), at: t(4))
        tellClean(&flagged, second, at: 10)
        flagged.observe(.extractorFlags(second, .none), at: t(14))
        #expect(flagged.decide(offer(.aboutApp), at: t(15)) == .stayQuiet(.gate), "heavy flags on an earlier segment")
        #expect(flagged.decide(offer(.reflection), at: t(15)) == .stayQuiet(.heavy))
    }

    @Test func extractorFlagsThatArrivedMustBeCleanToo() {
        var p = policy()
        tellClean(&p, first, at: 0)
        p.observe(.extractorFlags(first, Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: true)), at: t(4))
        #expect(p.decide(offer(.aboutApp), at: t(5)) == .speak, "a change of subject is not heavy")

        var q = policy()
        tellClean(&q, first, at: 0)
        q.observe(.extractorFlags(first, Flags(disclosure: .none, wantsToStop: true, wantsToChangeSubject: false)), at: t(4))
        #expect(q.decide(offer(.aboutApp), at: t(5)) == .stayQuiet(.gate))
        #expect(q.decide(offer(.wrapUp), at: t(5)) == .stayQuiet(.gate))
    }

    // MARK: Rule 5

    @Test func aStaleReplyIsDropped() {
        var p = policy()
        tellClean(&p, first, at: 0)
        p.observe(.speechStarted, at: t(4.5))
        p.observe(.userPaused, at: t(5))
        #expect(p.decide(offer(.reflection, requestedAt: 4), at: t(6.5)) == .stayQuiet(.stale))
        #expect(p.decide(offer(.reflection, requestedAt: 5.5), at: t(6.5)) == .speak)
    }

    // MARK: Rule 6

    @Test func neverTwoTurnsWithoutAStoredSegment() {
        var p = policy()
        tellClean(&p, first, at: 0)
        speak(&p, .reflection, at: 5)
        #expect(p.decide(offer(.wrapUp), at: t(7)) == .stayQuiet(.noSegmentSince))
        p.observe(.speechStarted, at: t(8))
        p.observe(.userPaused, at: t(9))
        #expect(p.decide(offer(.wrapUp), at: t(10)) == .stayQuiet(.noSegmentSince), "a pause that stored nothing")
        tellClean(&p, second, at: 11)
        #expect(p.decide(offer(.wrapUp), at: t(16)) == .speak)
    }

    @Test func aFixedTurnAfterADisclosureMayFollowAtOnce() {
        var p = policy()
        tell(&p, first, at: 0, check: pastDisclosure)
        speak(&p, .disclosure, at: 5)
        #expect(p.decide(offer(.earlyWindDown), at: t(6.1)) == .speak)
        #expect(p.decide(offer(.disclosure), at: t(6.1)) == .speak, "a present disclosure after a past one")
    }

    // MARK: Rule 7

    @Test func noQuestionWithinTwoTurnsOfAQuestion() {
        var p = policy()
        tellClean(&p, first, at: 0)
        speak(&p, .question, at: 5)
        tellClean(&p, second, at: 7)
        #expect(p.decide(offer(.question), at: t(12)) == .stayQuiet(.questionTooSoon))
        speak(&p, .reflection, at: 12)
        tellClean(&p, third, at: 14)
        #expect(p.decide(offer(.question), at: t(19)) == .stayQuiet(.questionTooSoon), "two turns after")
        speak(&p, .reflection, at: 19)
        tellClean(&p, fourth, at: 21)
        #expect(p.decide(offer(.question), at: t(26)) == .speak)
    }

    @Test func theOpeningCountsAsAQuestion() {
        var p = policy()
        speak(&p, .opening, at: 0)
        tellClean(&p, first, at: 2)
        #expect(p.decide(offer(.question), at: t(7)) == .stayQuiet(.questionTooSoon))
        #expect(p.decide(offer(.reflection), at: t(7)) == .speak)
    }

    // MARK: Rule 8

    @Test func aReplyIsRequestedOnlyAfterTheGrace() {
        var p = policy()
        tell(&p, first, at: 0, checked: false)
        #expect(p.segmentAwaitingReply(at: t(4.4)) == nil, "1.4 s after the pause")
        #expect(p.segmentAwaitingReply(at: t(4.5)) == first)
        tell(&p, second, at: 4.6, checked: false)
        #expect(p.segmentAwaitingReply(at: t(9.1)) == second, "the newer of two segments")
        p.observe(.interviewerCheck(second, clean), at: t(9.5))
        #expect(p.segmentAwaitingReply(at: t(10)) == nil, "asked once")
    }

    @Test func noReplyRequestAfterSpeechOrATurn() {
        var p = policy()
        tell(&p, first, at: 0, checked: false)
        p.observe(.speechStarted, at: t(3.5))
        p.observe(.userPaused, at: t(4))
        #expect(p.segmentAwaitingReply(at: t(10)) == nil, "the person spoke again")

        var q = policy()
        tell(&q, first, at: 0, checked: false)
        speak(&q, .wrapUp, at: 3.5)
        #expect(q.segmentAwaitingReply(at: t(10)) == nil, "a turn was spoken since")
    }

    @Test func noSegmentNoReplyRequest() {
        var p = policy()
        #expect(p.segmentAwaitingReply(at: t(10)) == nil)
        p.observe(.speechStarted, at: t(11))
        p.observe(.userPaused, at: t(12))
        #expect(p.segmentAwaitingReply(at: t(20)) == nil, "a segment emptied of the app's words is never stored")
    }

    @Test func noReplyRequestInAQuickStoryWhenQuietAfterHeavyOrInWindDown() {
        var quick = policy(.quick)
        tell(&quick, first, at: 0, checked: false)
        #expect(quick.segmentAwaitingReply(at: t(10)) == nil)

        var quiet = policy()
        quiet.observe(.quiet(true), at: t(0))
        tell(&quiet, first, at: 0, checked: false)
        #expect(quiet.segmentAwaitingReply(at: t(10)) == nil)

        var heavy = policy()
        tellClean(&heavy, first, at: 0)
        heavy.observe(.extractorFlags(first, Flags(disclosure: .present, wantsToStop: false, wantsToChangeSubject: false)), at: t(4))
        tell(&heavy, second, at: 5, checked: false)
        #expect(heavy.segmentAwaitingReply(at: t(20)) == nil)

        var latched = policy()
        tell(&latched, first, at: 0, check: pastDisclosure)
        tell(&latched, second, at: 5, checked: false)
        #expect(latched.segmentAwaitingReply(at: t(20)) == nil)

        var windDown = policy()
        windDown.observe(.stage(.windDown), at: t(0))
        tell(&windDown, first, at: 0, checked: false)
        #expect(windDown.segmentAwaitingReply(at: t(10)) == nil)
    }

    // MARK: Rule 9

    @Test func nextQuestionIsNeverSpoken() {
        // The 6 s next question has no kind, so it can never be offered. `question` is the model's follow-up.
        #expect(Set(TurnKind.allCases) == [.opening, .reflection, .question, .wrapUp, .earlyWindDown, .disclosure, .aboutApp])
    }

    // MARK: Rule 10

    @Test func windDownAllowsOnlyWrapUpAndFixedTurns() {
        var p = policy()
        tellClean(&p, first, at: 0)
        p.observe(.stage(.windDown), at: t(4))
        #expect(p.decide(offer(.reflection), at: t(5)) == .stayQuiet(.windDown))
        #expect(p.decide(offer(.question), at: t(5)) == .stayQuiet(.windDown))
        for kind in [TurnKind.wrapUp, .aboutApp, .disclosure, .earlyWindDown] {
            #expect(p.decide(offer(kind), at: t(5)) == .speak, "\(kind)")
        }
    }

    // MARK: Session kinds

    @Test func quickStorySpeaksOnlyOpeningDisclosureAndWindDown() {
        var p = policy(.quick)
        #expect(p.decide(offer(.opening), at: t(0)) == .speak)
        tellClean(&p, first, at: 1)
        for kind in [TurnKind.reflection, .question, .wrapUp, .aboutApp] {
            #expect(p.decide(offer(kind), at: t(6)) == .stayQuiet(.quickStory), "\(kind)")
        }
        #expect(p.decide(offer(.disclosure), at: t(6)) == .speak)
        #expect(p.decide(offer(.earlyWindDown), at: t(6)) == .speak)
    }

    @Test func theOpeningIsNotSpokenAfterSpeechStarted() {
        var p = policy()
        p.observe(.speechStarted, at: t(1))
        p.observe(.userPaused, at: t(2))
        #expect(p.decide(offer(.opening), at: t(4)) == .stayQuiet(.openingTooLate))
    }

    // MARK: Precedence

    @Test func reasonsFollowTheSpecsPrecedence() {
        var p = policy()
        tell(&p, first, at: 0, checked: false)
        p.observe(.extractorFlags(first, Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false)), at: t(4))
        p.observe(.quiet(true), at: t(4))
        p.observe(.speechStarted, at: t(5))
        #expect(p.decide(offer(.reflection), at: t(6)) == .stayQuiet(.personSpeaking))
        p.observe(.userPaused, at: t(6))
        #expect(p.decide(offer(.reflection), at: t(8)) == .stayQuiet(.heavy))
        #expect(p.decide(offer(.wrapUp), at: t(8)) == .stayQuiet(.quiet))
        p.observe(.quiet(false), at: t(8))
        #expect(p.decide(offer(.wrapUp), at: t(8)) == .stayQuiet(.gate))
    }

    // MARK: Check-only calls and failed checks (fix round 1)

    @Test func aSegmentAwaitsACheckInWindDown() {
        var p = policy()
        tell(&p, first, at: 1, checked: false)
        p.observe(.stage(.windDown), at: t(4.2))
        #expect(p.segmentAwaitingReply(at: t(5.5)) == nil, "no reply in windDown")
        #expect(p.segmentAwaitingCheck(at: t(5.4)) == nil, "before the grace")
        #expect(p.segmentAwaitingCheck(at: t(5.5)) == first)
        #expect(p.checkStillPossible)
        p.observe(.interviewerCheck(first, clean), at: t(5.6))
        #expect(p.segmentAwaitingCheck(at: t(6)) == nil, "a check arrived")
        #expect(!p.checkStillPossible)
    }

    @Test func noSegmentAwaitsACheckInAQuickStoryOrWhenQuiet() {
        var quick = policy(.quick)
        tell(&quick, first, at: 1, checked: false)
        quick.observe(.stage(.windDown), at: t(4.2))
        #expect(quick.segmentAwaitingCheck(at: t(6)) == nil && !quick.checkStillPossible)
        var quiet = policy()
        tell(&quiet, first, at: 1, checked: false)
        quiet.observe(.stage(.windDown), at: t(4.2))
        quiet.observe(.quiet(true), at: t(4.3))
        #expect(quiet.segmentAwaitingCheck(at: t(6)) == nil && !quiet.checkStillPossible)
    }

    @Test func noSegmentAwaitsACheckAfterTheLatch() {
        var unclean = policy()
        tell(&unclean, first, at: 1, check: pastDisclosure)
        tell(&unclean, second, at: 10, checked: false)
        unclean.observe(.stage(.windDown), at: t(13.2))
        #expect(unclean.segmentAwaitingCheck(at: t(15)) == nil && !unclean.checkStillPossible)
        var heavy = policy()
        tell(&heavy, first, at: 1, checked: false)
        heavy.observe(.extractorFlags(first, Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false)), at: t(4.1))
        heavy.observe(.stage(.windDown), at: t(4.2))
        #expect(heavy.segmentAwaitingCheck(at: t(6)) == nil && !heavy.checkStillPossible)
    }

    @Test func aFailedCheckHoldsTheGateUntilItsFlagsArrive() {
        var p = policy()
        tell(&p, first, at: 1, check: nil)
        tellClean(&p, second, at: 10)
        #expect(p.decide(offer(.reflection, requestedAt: 13.2), at: t(14)) == .stayQuiet(.gate))
        #expect(p.gateWaitsForFlags)
        p.observe(.extractorFlags(first, Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: false)), at: t(15))
        #expect(!p.gateWaitsForFlags)
        #expect(p.decide(offer(.reflection, requestedAt: 13.2), at: t(15)) == .speak)
    }

    @Test func aFailedNewestCheckDoesNotWaitForFlags() {
        var p = policy()
        tell(&p, first, at: 1, check: nil)
        #expect(!p.gateWaitsForFlags, "flags alone cannot open the gate: the newest segment has no clean check")
    }
}
