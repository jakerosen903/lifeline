import Foundation
import Testing
@testable import LifelineKit

/// Calls the real model. Opt in with ANTHROPIC_API_KEY in the environment; skipped otherwise.
/// The one assertion that matters: nothing shown to the owner contains text they did not say.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil), .serialized)
struct ExtractorIntegrationTests {
    static let olderFixtures = ["transcript-garden", "transcript-roadtrip", "transcript-school"]
    /// The PC-d test stories. Each fixture holds its expected answer (`expected_people`).
    static let handleStories = ["transcript-v8-two-robyns", "transcript-v8-two-names", "transcript-v8-name-alone", "transcript-v8-new-relation"]
    static let comparedVersions = ["v6", "v8"]
    static let runsPerVersion = 3
    static let tableFile = FileManager.default.temporaryDirectory.appendingPathComponent("extractor-v8-handles.md")

    @Test(arguments: olderFixtures)
    func noFieldContainsTextAbsentFromTheTranscript(fixture: String) async throws {
        let run = try await Self.extract(fixture, version: ExtractorConfig.default.version)
        #expect(run.segments.allSatisfy { $0.status == .extracted }, "every segment extracted: \(run.segments.map(\.status))")
        let shown = try Self.expectShownFieldsAreTheOwnersWords(run, label: fixture)
        #expect(shown > 0, "the model proposed nothing for \(fixture)")
    }

    /// PC-d Task 7: every story and older fixture through `v6` and `v8`, three runs each. The expected answer
    /// is reported in the table, not asserted: `v6` gives no handles and is expected to miss two Robyns.
    /// The table goes to `tableFile` row by row, and each row is printed as it is made: a failure in a
    /// later run keeps the earlier rows.
    @Test func v6AgainstV8OnPeopleHandles() async throws {
        let header = Self.tableHeader.joined(separator: "\n") + "\n"
        try header.write(to: Self.tableFile, atomically: true, encoding: .utf8)
        print(header, terminator: "")
        print("[comparison] table goes to \(Self.tableFile.path)")
        for fixture in Self.handleStories + Self.olderFixtures {
            for version in Self.comparedVersions {
                for index in 1...Self.runsPerVersion {
                    let run = try await Self.extract(fixture, version: version)
                    let label = "\(fixture) \(version) run \(index)"
                    _ = try Self.expectShownFieldsAreTheOwnersWords(run, label: label)
                    try Self.expectEveryMemoryHandleNamesAKnownPerson(run, label: label)
                    let row = try Self.tableRow(run, run: index)
                    try Self.appendToTable(row + "\n")
                    print(row)
                }
            }
        }
        print("[comparison] table written to \(Self.tableFile.path)")
    }

    static func appendToTable(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: tableFile)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    // MARK: - One run of one fixture

    /// One fixture extracted segment by segment through the real queue: each later segment gets the earlier
    /// segments' text and, from the stored cards, the recording's people (`recordingPeople`), as on device.
    struct Run {
        let fixture: String
        let version: String
        let store: ExtractionStore
        let segments: [Segment]
        let expected: [[String]]?
    }

    static func extract(_ fixture: String, version: String) async throws -> Run {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures"))
        let store = ExtractionStore(try AppDatabase.inMemory())
        let session = try TranscriptImport.importTranscript(at: url, into: store.sessions)
        let service = AnthropicExtractionService(config: ExtractorConfig(version: version),
                                                 apiKey: { ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] })
        // Three segments of real calls take longer than the default 20 s drain.
        let queue = ExtractionQueue(session: session, service: service, store: store, drainDeadline: .seconds(600),
                                    log: { print("[integration] \(fixture) \(version): \($0)") })
        for segment in try store.sessions.segments(in: session) { await queue.enqueue(segment.id) }
        await queue.drain()
        return Run(fixture: fixture, version: version, store: store, segments: try store.sessions.segments(in: session),
                   expected: try HandleTally.expectedPeople(inFixture: Data(contentsOf: url)))
    }

    /// The rows the pass kept as cards or records: everything but rejected and withheld rows.
    static func keptRows(of segment: Segment, in run: Run) throws -> [Candidate] {
        try run.store.candidates.candidates(for: segment.id).filter { $0.status != .dismissed }
    }

    // MARK: - What must hold for every version

    /// Every shown field is copied from the transcript. A person's said name may come from an earlier
    /// segment of the recording (D17), so it is checked against the recording so far. Returns the number of shown cards.
    static func expectShownFieldsAreTheOwnersWords(_ run: Run, label: String) throws -> Int {
        var shown = 0
        for (position, segment) in run.segments.enumerated() {
            let haystack = OutputValidator.normalize(segment.text)
            let recordingSoFar = OutputValidator.normalize(run.segments[...position].map(\.text).joined(separator: " "))
            for candidate in try run.store.candidates.candidates(for: segment.id) where candidate.status == .pending {
                shown += 1
                if let m = CandidatePayload.memory(candidate) {
                    #expect(OutputValidator.contains(haystack, m.quote), "\(label) quote: \(m.quote)")
                    for p in m.peopleRefs { #expect(OutputValidator.contains(recordingSoFar, p), "\(label) people_ref: \(p)") }
                    if let place = m.placeText { #expect(OutputValidator.contains(haystack, place), "\(label) place: \(place)") }
                    for a in m.anchors { #expect(OutputValidator.contains(haystack, a.phrase), "\(label) anchor: \(a.phrase)") }
                    #expect(m.title.split(whereSeparator: \.isWhitespace).count <= 8, "\(label) title: \(m.title)")
                    print("[integration] \(label) memory: \(m.title) | \(m.quote) | people \(m.peopleRefs) "
                          + "| handles \(m.personHandles) | anchors \(m.anchors.map(\.phrase))")
                } else if let mention = CandidatePayload.mention(candidate) {
                    #expect(OutputValidator.contains(haystack, mention.text), "\(label) mention: \(mention.text)")
                    print("[integration] \(label) mention: \(mention.text) (\(mention.kind)) handle \(mention.handle ?? "-")")
                }
            }
        }
        return shown
    }

    /// Every handle of a stored memory names a person of that output's `people` or of the recording so far (D17).
    static func expectEveryMemoryHandleNamesAKnownPerson(_ run: Run, label: String) throws {
        for segment in run.segments {
            let session = segment.sessionID
            let recording = Set(try run.store.candidates.handlePeople(inSession: session, before: segment.id).map(\.handle))
            for memory in try keptRows(of: segment, in: run).compactMap(CandidatePayload.memory) {
                let known = recording.union(memory.handlePeople.map(\.handle))
                #expect(Set(memory.personHandles).isSubset(of: known), "\(label) handles \(memory.personHandles), known \(known.sorted())")
            }
        }
    }

    // MARK: - The table

    static let tableHeader = [
        "| Story | Version | Run | People found | People (handle: said names) | Expected | Pass | Memories | Mentions | Segments not extracted |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]

    static func tableRow(_ run: Run, run index: Int) throws -> String {
        var outputs: [ExtractorOutput] = []
        var memories = 0, mentions = 0
        for segment in run.segments {
            let rows = try keptRows(of: segment, in: run)
            let segmentMemories = rows.compactMap(CandidatePayload.memory)
            let segmentMentions = rows.compactMap(CandidatePayload.mention)
            memories += segmentMemories.count
            mentions += segmentMentions.count
            outputs.append(ExtractorOutput(memories: segmentMemories, mentions: segmentMentions, flags: .none))
        }
        let tally = HandleTally(outputs: outputs)
        let people = tally.people.map { ($0.handle.map { "\($0): " } ?? "") + $0.saidNames.joined(separator: " / ") }.joined(separator: "; ")
        let expected = run.expected.map { String($0.count) } ?? "—"
        let pass = run.expected.map { tally.holds($0) ? "yes" : "no" } ?? "—"
        let unextracted = run.segments.filter { $0.status != .extracted }.count
        let story = run.fixture.replacingOccurrences(of: "transcript-", with: "")
        return "| \(story) | \(run.version) | \(index) | \(tally.people.count) | \(people.isEmpty ? "—" : people) | \(expected) | \(pass) "
            + "| \(memories) | \(mentions) | \(unextracted) |"
    }
}
