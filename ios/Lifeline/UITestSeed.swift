import Foundation
import LifelineKit

/// Under `-uiTesting-seed`: a kept person and a full timeline, written before the first screen,
/// for tests about the shell rather than about recording. Invented content only.
enum UITestSeed {
    static let person = "Maya"
    static let firstYear = 1980
    static let memoryCount = 12

    /// One landed session with a segment per memory, each kept as a moment in its own year.
    /// The segments are already sorted, so the worker leaves them alone.
    static func write(sessions: SessionRepository, store: ExtractionStore) throws {
        _ = try store.people.insertPerson(displayName: person)
        let session = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(session)
        for index in 0..<memoryCount {
            let year = firstYear + index
            let text = "the summer of \(year) at the lake"
            let segment = Segment(id: .init(), sessionID: session.id, index: index, startMs: index * 5_000, endMs: index * 5_000 + 4_000,
                                  text: text, status: .extracted)
            try sessions.insert(segment, words: [])
            let candidate = Candidate(id: .init(), segmentID: segment.id, extractorVersion: "seed", ordinal: 0, kind: .memory, payload: "{}",
                                      confidence: 1, status: .pending, rejection: nil, createdAt: .now)
            try store.candidates.insert(candidate)
            let memory = Memory(id: .init(), title: "The lake in \(year)", summaryQuote: text, visibility: .timeline, chapterID: nil,
                                createdFromCandidateID: candidate.id, createdAt: .now, range: .year(year, origin: .stated, evidence: "in \(year)"))
            try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: segment.startMs, endMs: segment.endMs, order: 0)],
                                      people: [], places: [], anchors: [], acceptingCandidate: candidate.id)
        }
    }
}
