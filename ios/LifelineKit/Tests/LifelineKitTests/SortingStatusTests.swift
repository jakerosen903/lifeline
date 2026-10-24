import Foundation
import Testing
@testable import LifelineKit

private func session(startedAt: Date) -> Session {
    Session(id: .init(), startedAt: startedAt, endedAt: startedAt.addingTimeInterval(60), audioPath: "a.m4a", stageLog: "[]", landingChoiceMade: true)
}

@Test func sortingLineCoversEveryState() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_761_307_200)        // 2026-10-24 12:00 UTC, a Saturday
    let today = session(startedAt: now.addingTimeInterval(-3_600))
    let wednesday = session(startedAt: now.addingTimeInterval(-2 * 86_400))
    let old = session(startedAt: now.addingTimeInterval(-30 * 86_400))
    func status(_ pending: [(Session, Int)], active: Bool = false, failure: ExtractionError? = nil, checking: Bool = false, hasKey: Bool = true) -> SortingStatus {
        SortingStatus(pending: pending.map { SortingStatus.Pending(session: $0.0, count: $0.1) }, active: active, lastFailure: failure, checkingRepeats: checking, hasKey: hasKey)
    }
    #expect(status([]).line(now: now, calendar: cal) == nil)
    #expect(status([]).isEmpty)
    #expect(status([(today, 2)], active: true).line(now: now, calendar: cal) == "Still sorting 2 moments from today's recording…")
    #expect(status([(today, 1)], active: true).line(now: now, calendar: cal) == "Still sorting 1 moment from today's recording…")
    #expect(status([(wednesday, 3)], active: true).line(now: now, calendar: cal) == "Still sorting 3 moments from Wednesday's recording…")
    #expect(status([(old, 1)], active: true).line(now: now, calendar: cal) == "Still sorting 1 moment from Sep 24's recording…")
    #expect(status([(today, 1), (wednesday, 1)], active: true).line(now: now, calendar: cal) == "Still sorting 2 moments from 2 recordings…")
    #expect(status([], checking: true).line(now: now, calendar: cal) == "Checking for repeats…")
    #expect(status([(today, 2)], active: false).line(now: now, calendar: cal) == "Not sorting right now")
    #expect(status([(today, 2)], active: false, failure: .network("x")).line(now: now, calendar: cal) == "Not sorting right now")
    #expect(status([(today, 2)], active: false, failure: .noKey).line(now: now, calendar: cal) == "Add a key in Settings to sort what you say")
    #expect(status([(today, 2)], active: true, hasKey: false).line(now: now, calendar: cal) == "Add a key in Settings to sort what you say", "key line first")
    #expect(status([(today, 2)], active: true, checking: true).line(now: now, calendar: cal)?.hasPrefix("Still sorting") == true, "still sorting beats checking")
    #expect(status([(today, 2)], active: false).needsKey == false && status([(today, 1)], failure: .noKey).needsKey)
    #expect(status([(today, 2)], active: false).canRetry && !status([(today, 2)], active: true).canRetry)
}

@Test func statusEmptiesWhenTheLastSegmentLands() throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: ["one", "two"])
    try store.sessions.setStatus(.extracted, for: segs[0].id)
    let reporter = SortingReporter()
    var status = try SortingStatus.current(store: store, reporter: reporter, hasKey: true)
    #expect(status.pending.map(\.count) == [1] && !status.isEmpty)
    try store.sessions.setStatus(.extracted, for: segs[1].id)
    status = try SortingStatus.current(store: store, reporter: reporter, hasKey: true)
    #expect(status.isEmpty)
}

@Test func reporterCountsOverlappingActivity() {
    let reporter = SortingReporter()
    let changes = LogCollector()
    reporter.onChange = { changes.append("x") }
    reporter.activityChanged(active: true)
    reporter.activityChanged(active: true)
    reporter.activityChanged(active: false)
    #expect(reporter.snapshot().active, "one of two is still running")
    reporter.activityChanged(active: false)
    #expect(!reporter.snapshot().active)
    reporter.failed(.network("down"))
    #expect(reporter.snapshot().lastFailure == .network("down"))
    reporter.cleared()
    #expect(reporter.snapshot().lastFailure == nil)
    reporter.passChanged(running: true)
    #expect(reporter.snapshot().checkingRepeats)
    #expect(changes.all.count >= 6, "every change is announced")
}
