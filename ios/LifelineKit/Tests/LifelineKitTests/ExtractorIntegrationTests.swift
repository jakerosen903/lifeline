import Foundation
import Testing
@testable import LifelineKit

/// Calls the real model. Opt in with ANTHROPIC_API_KEY in the environment; skipped otherwise.
/// The one assertion that matters: nothing shown to the owner contains text they did not say.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil), .serialized)
struct ExtractorIntegrationTests {
    @Test(arguments: ["transcript-garden", "transcript-roadtrip", "transcript-school"])
    func noFieldContainsTextAbsentFromTheTranscript(fixture: String) async throws {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures"))
        let db = try AppDatabase.inMemory()
        let store = ExtractionStore(db)
        let session = try TranscriptImport.importTranscript(at: url, into: store.sessions)
        let service = AnthropicExtractionService(apiKey: { ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] })
        let queue = ExtractionQueue(session: session, service: service, store: store, log: { print("[integration] \($0)") })
        for segment in try store.sessions.segments(in: session) { await queue.enqueue(segment.id) }
        await queue.drain()

        let segments = try store.sessions.segments(in: session)
        #expect(segments.allSatisfy { $0.status == .extracted }, "every segment extracted: \(segments.map(\.status))")
        var shown = 0
        for segment in segments {
            let haystack = OutputValidator.normalize(segment.text)
            for candidate in try store.candidates.candidates(for: segment.id) where candidate.status == .pending {
                shown += 1
                if let m = CandidatePayload.memory(candidate) {
                    #expect(OutputValidator.contains(haystack, m.quote), "quote: \(m.quote)")
                    for p in m.peopleRefs { #expect(OutputValidator.contains(haystack, p), "people_ref: \(p)") }
                    if let place = m.placeText { #expect(OutputValidator.contains(haystack, place), "place: \(place)") }
                    for a in m.anchors { #expect(OutputValidator.contains(haystack, a.phrase), "anchor: \(a.phrase)") }
                    #expect(m.title.split(whereSeparator: \.isWhitespace).count <= 8, "title: \(m.title)")
                    print("[integration] \(fixture) memory: \(m.title) | \(m.quote) | people \(m.peopleRefs) | anchors \(m.anchors.map(\.phrase))")
                } else if let mention = CandidatePayload.mention(candidate) {
                    #expect(OutputValidator.contains(haystack, mention.text), "mention: \(mention.text)")
                    print("[integration] \(fixture) mention: \(mention.text) (\(mention.kind))")
                }
            }
        }
        #expect(shown > 0, "the model proposed nothing for \(fixture)")
    }
}
