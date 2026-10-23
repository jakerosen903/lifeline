import Foundation
import Testing
@testable import LifelineKit

private func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
}

private func gardenOutput() -> ExtractorOutput {
    ExtractorOutput(memories: [MemoryOut(ref: "m1", title: "The pomegranate tree", quote: "the garden behind the house had a pomegranate tree",
                                         segmentSpan: WordSpan(startWord: 0, endWord: 8), peopleRefs: [], placeText: nil, anchors: [],
                                         sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)],
                    mentions: [MentionOut(text: "the garden", kind: .place, likelyAliasOfPersonID: nil, confidence: 0.5)], flags: .none)
}

@Test func extractPrintsCandidatesAndSummary() async throws {
    let db = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
    let imported = try await CLI.run(["import", try fixture("transcript-garden").path(), "--db", db.path()])
    let sessionID = imported.output.trimmingCharacters(in: .whitespacesAndNewlines)
    let service = FakeExtractionService([.success(gardenOutput())])
    let result = try await CLI.run(["extract", "--session", sessionID, "--db", db.path()], environment: [:], service: service)
    #expect(result.exitCode == 0, Comment(rawValue: result.output))
    let lines = result.output.split(separator: "\n")
    #expect(lines.filter { $0.hasPrefix("0\t") }.count == 2, Comment(rawValue: result.output))
    #expect(lines.contains { $0.contains("memory\tpending\t0.90\tThe pomegranate tree") }, Comment(rawValue: result.output))
    #expect(lines.last == "2 candidates, 0 rejected, 0 failed segments", Comment(rawValue: result.output))
    #expect(service.requests.count == 3)
    let repo = SessionRepository(try AppDatabase.open(at: db))
    #expect(try repo.segments(in: SessionID(rawValue: sessionID), status: .pending).isEmpty)
}

@Test func extractReportsRejectionsAndFailures() async throws {
    let db = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
    let imported = try await CLI.run(["import", try fixture("transcript-garden").path(), "--db", db.path()])
    let sessionID = imported.output.trimmingCharacters(in: .whitespacesAndNewlines)
    var invented = gardenOutput()
    invented.memories[0].quote = "we drove to Yosemite"
    // Two segments fail, and fail again when drain retries them.
    let service = FakeExtractionService([.success(invented), .failure(.unauthorized), .failure(.unauthorized), .failure(.unauthorized), .failure(.unauthorized)])
    let result = try await CLI.run(["extract", "--session", sessionID, "--db", db.path()], environment: [:], service: service)
    #expect(result.exitCode == 0)
    #expect(result.output.contains("memory\tdismissed\t0.90\tThe pomegranate tree\tquote not in segment"))
    #expect(result.output.hasSuffix("2 candidates, 1 rejected, 2 failed segments\n"), Comment(rawValue: result.output))
}

@Test func extractWithoutKeyExitsThree() async throws {
    let db = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
    let imported = try await CLI.run(["import", try fixture("transcript-garden").path(), "--db", db.path()])
    let sessionID = imported.output.trimmingCharacters(in: .whitespacesAndNewlines)
    let result = try await CLI.run(["extract", "--session", sessionID, "--db", db.path()], environment: [:])
    #expect(result.exitCode == 3 && result.output.contains("ANTHROPIC_API_KEY is not set"))
}

@Test func extractNeedsASessionThatExists() async throws {
    let db = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
    let result = try await CLI.run(["extract", "--session", "nope", "--db", db.path()], environment: [:], service: FakeExtractionService())
    #expect(result.exitCode == 2 && result.output.contains("no session"))
}
