import Foundation
import Testing
@testable import LifelineKit

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
private func arc(_ kind: SessionKind) -> SessionArc { SessionArc(kind: kind, config: .default, startedAt: start) }
private func flags(disclosure: DisclosureKind = .none, stop: Bool = false, change: Bool = false) -> Flags {
    Flags(disclosure: disclosure, wantsToStop: stop, wantsToChangeSubject: change)
}

@Test func startsOpenWithOneLogEntry() {
    let a = arc(.quick)
    #expect(a.stage == .open && a.log.map(\.reason) == ["started"] && !a.heavy)
}

@Test func quickStoryHasNoTimeElementAtAll() {
    var a = arc(.quick)
    var effects: [ArcEffect] = []
    for minute in stride(from: 1.0, through: 60, by: 1) {
        if let e = a.apply(.tick(elapsed: .seconds(minute * 60)), now: at(minute * 60)) { effects.append(e) }
    }
    #expect(effects.isEmpty && a.stage == .open && a.log.count == 1)
}

@Test func settleInOffersWrapUpAtThePlannedLengthAndNeverStops() {
    var a = arc(.settleIn)
    #expect(a.apply(.tick(elapsed: .seconds(29 * 60)), now: at(29 * 60)) == nil)
    #expect(a.apply(.tick(elapsed: .seconds(30 * 60)), now: at(30 * 60)) == .offerWrapUp(.plannedLength))
    #expect(a.stage == .windDown && a.wrapUpOffered && a.log.last?.reason == "plannedLength")
    #expect(a.apply(.tick(elapsed: .seconds(31 * 60)), now: at(31 * 60)) == nil, "offered once")
    for minute in 32...170 { _ = a.apply(.tick(elapsed: .seconds(minute * 60)), now: at(Double(minute) * 60)) }
    #expect(a.stage == .windDown, "nothing stops a session on its own before the recording limit")
}

@Test func keepGoingOffersAgainAfterTheGrace() {
    var a = arc(.settleIn)
    _ = a.apply(.tick(elapsed: .seconds(30 * 60)), now: at(30 * 60))
    #expect(a.apply(.keepGoing, now: at(30 * 60 + 5)) == nil && a.log.last?.reason == "keepGoing")
    #expect(a.apply(.tick(elapsed: .seconds(35 * 60)), now: at(35 * 60)) == nil)
    #expect(a.apply(.tick(elapsed: .seconds(40 * 60 + 5)), now: at(40 * 60 + 5)) == .offerWrapUp(.plannedLength))
}

@Test func finishLandsFromAnyStage() {
    var open = arc(.quick)
    #expect(open.apply(.finish, now: at(90)) == .land && open.stage == .ended && open.log.last?.reason == "finish")
    var winding = arc(.settleIn)
    _ = winding.apply(.tick(elapsed: .seconds(30 * 60)), now: at(30 * 60))
    #expect(winding.apply(.finish, now: at(31 * 60)) == .land && winding.stage == .ended)
}

@Test func recordingLimitIsTheOnlyAutomaticLanding() {
    var a = arc(.quick)
    #expect(a.apply(.tick(elapsed: .seconds(3 * 3600 - 1)), now: at(3 * 3600 - 1)) == nil)
    #expect(a.apply(.tick(elapsed: .seconds(3 * 3600)), now: at(3 * 3600)) == .land && a.log.last?.reason == "recordingLimit")
}

@Test func wantsToStopWindsDown() {
    var a = arc(.quick)
    #expect(a.apply(.flags(flags(stop: true)), now: at(60)) == .offerWrapUp(.wantsToStop))
    #expect(a.stage == .windDown && a.heavy && a.log.last?.reason == "wantsToStop")
}

@Test func disclosureShowsTheCardAndMarksHeavy() {
    var a = arc(.settleIn)
    #expect(a.apply(.flags(flags(disclosure: .past)), now: at(60)) == .showDisclosureCard(.past))
    #expect(a.stage == .windDown && a.heavy && a.log.last?.reason == "disclosure")
    #expect(a.apply(.flags(flags(disclosure: .present)), now: at(120)) == .showDisclosureCard(.present))
    #expect(a.apply(.flags(flags(disclosure: .present)), now: at(180)) == nil, "never a third card")
    #expect(a.log.filter { $0.reason.hasPrefix("disclosure") }.count == 3, "but every disclosure is logged")
    #expect(a.presentDanger, "present danger is remembered for the landing")
}

@Test func presentAfterPastShowsTheCardAgain() {
    var a = arc(.quick)
    #expect(a.apply(.flags(flags(disclosure: .past)), now: at(60)) == .showDisclosureCard(.past))
    #expect(a.apply(.flags(flags(disclosure: .present)), now: at(120)) == .showDisclosureCard(.present))
    #expect(a.apply(.flags(flags(disclosure: .past)), now: at(180)) == nil)
    #expect(a.apply(.flags(flags(disclosure: .present)), now: at(240)) == nil)
}

@Test func presentFirstShowsTheCardOnce() {
    var a = arc(.quick)
    #expect(a.apply(.flags(flags(disclosure: .present)), now: at(60)) == .showDisclosureCard(.present))
    #expect(a.apply(.flags(flags(disclosure: .past)), now: at(120)) == nil)
}

@Test func plannedLengthAndGraceGiveThePlannedReason() {
    var a = arc(.settleIn)
    #expect(a.apply(.tick(elapsed: .seconds(30 * 60)), now: at(30 * 60)) == .offerWrapUp(.plannedLength))
    _ = a.apply(.keepGoing, now: at(30 * 60 + 5))
    #expect(a.apply(.tick(elapsed: .seconds(40 * 60 + 5)), now: at(40 * 60 + 5)) == .offerWrapUp(.plannedLength))
}

@Test func wantsToStopGivesTheWantsToStopReason() {
    var a = arc(.settleIn)
    #expect(a.apply(.flags(flags(stop: true)), now: at(60)) == .offerWrapUp(.wantsToStop))
}

@Test func changeSubjectOnlyLogs() {
    var a = arc(.quick)
    #expect(a.apply(.flags(flags(change: true)), now: at(60)) == nil && a.stage == .open && a.log.last?.reason == "changeSubject")
}

@Test func signalsAfterEndedAreIgnored() {
    var a = arc(.quick)
    _ = a.apply(.finish, now: at(60))
    #expect(a.apply(.flags(flags(disclosure: .past)), now: at(61)) == nil && a.log.count == 2)
    #expect(a.apply(.landed, now: at(62)) == nil && a.log.last?.reason == "landed")
}

@Test func logRoundTripsThroughJSON() throws {
    var a = arc(.settleIn)
    _ = a.apply(.tick(elapsed: .seconds(30 * 60)), now: at(30 * 60))
    _ = a.apply(.finish, now: at(31 * 60))
    let json = try SessionArc.encode(a.log)
    #expect(json.contains("\"plannedLength\""))
    #expect(try SessionArc.decode(json) == a.log)
}

@Test func uiTestingConfigIsShort() {
    #expect(ArcConfig.uiTesting.settleInPlanned < .seconds(30) && ArcConfig.uiTesting.recordingLimit < .seconds(120))
}
