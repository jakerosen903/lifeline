import Foundation
import GRDB
import Testing
@testable import LifelineKit

/// The repair's steps are separate writes. A step that fails must not hide what the steps before it
/// already changed: the person is told about every join that happened, and the later steps still run.
private struct Env {
    let db: AppDatabase, store: ExtractionStore
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        // As the old code left them: three stories with one title, and a chapter that holds nothing.
        for title in ["The road trip", "the road trip", "The road trip."] { try store.stories.insert(title: title, chapterID: nil) }
        _ = try store.chapters.insertChapter(title: nil)
    }

    /// Makes the collections step throw, as a damaged table would.
    func breakCollections() throws {
        try db.writer.write { try $0.execute(sql: "alter table collection rename to collection_gone") }
    }
}

@Test func aFailedStepKeepsWhatTheEarlierStepsJoined() throws {
    let env = try Env()
    try env.breakCollections()
    let report = ArchiveRepair.run(env.store)
    #expect(report.joinedStories == [StoryRepository.MergedTitle(title: "The road trip", copies: 3)])
    #expect(report.notice == "Joined 3 copies of “The road trip”.", "the stories were joined, so the person is told")
    #expect(report.failures.map(\.step) == [.collections])
    #expect(try env.store.stories.stories().count == 1)
}

@Test func theStepsAfterAFailedOneStillRun() throws {
    let env = try Env()
    try env.breakCollections()
    let report = ArchiveRepair.run(env.store)
    #expect(report.removedChapters == 1, "each step is independent: the chapters step comes after the one that failed")
    #expect(try env.store.chapters.chapters().isEmpty)
}

@Test func aFailedStepIsTriedAgainOnTheNextRun() throws {
    let env = try Env()
    try env.breakCollections()
    _ = ArchiveRepair.run(env.store)
    let again = ArchiveRepair.run(env.store)
    #expect(again.notice == nil, "what was joined is not joined or said twice")
    #expect(again.failures.map(\.step) == [.collections], "the step that failed is tried on every run until it works")
}

@Test func aRepairWithNoFailureReportsNone() throws {
    let report = ArchiveRepair.run(try Env().store)
    #expect(report.failures.isEmpty)
    #expect(report.notice == "Joined 3 copies of “The road trip”.")
}

@Test func aFailureAloneGivesNoNotice() throws {
    let db = try AppDatabase.inMemory()
    try db.writer.write { try $0.execute(sql: "alter table collection rename to collection_gone") }
    let report = ArchiveRepair.run(ExtractionStore(db))
    #expect(report.notice == nil, "nothing was joined, so there is nothing to tell the person")
    #expect(report.failures.count == 1)
}
