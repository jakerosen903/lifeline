import Foundation
import Testing
@testable import LifelineKit

private func fixtureURL() throws -> URL {
    try #require(Bundle.module.url(forResource: "transcript-garden", withExtension: "json", subdirectory: "Fixtures"))
}

@Test func importsFixtureAsSessionWithSegmentsAndWords() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let id = try TranscriptImport.importTranscript(at: try fixtureURL(), into: repo)
    let session = try #require(try repo.fetch(id))
    #expect(session.startedAt == Date(timeIntervalSince1970: 1_773_512_400))
    #expect(session.endedAt != nil)
    let segs = try repo.segments(in: id)
    #expect(segs.count == 3 && segs[0].index == 0 && segs[0].text.hasPrefix("the garden"))
    #expect(segs[1].range == MsRange(start: 7_000, end: 12_400))
    #expect(try repo.words(in: segs[0].id).count == segs[0].text.split(separator: " ").count)
}

@Test func rejectsASegmentWhoseWordsFallOutsideItsRange() throws {
    let json = """
    {"started_at":"2026-01-01T00:00:00Z","segments":[{"start_ms":0,"end_ms":1000,"words":[{"text":"late","start_ms":1500,"end_ms":1800}]}]}
    """
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    try json.write(to: url, atomically: true, encoding: .utf8)
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    #expect(throws: TranscriptImport.Error.self) { try TranscriptImport.importTranscript(at: url, into: repo) }
    #expect(try repo.listSessions().isEmpty)
}

@Test func cliRunsImportAndSessions() async throws {
    let db = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
    let imported = try await CLI.run(["import", try fixtureURL().path(), "--db", db.path()])
    #expect(imported.exitCode == 0 && imported.output.count == 37)   // a UUID and a newline
    let listed = try await CLI.run(["sessions", "--db", db.path()])
    #expect(listed.exitCode == 0 && listed.output.contains("3 segments"))
    #expect(try await CLI.run(["bogus"]).exitCode == 2)
    #expect(try await CLI.run(["sessions"]).exitCode == 2)   // --db is required
}
