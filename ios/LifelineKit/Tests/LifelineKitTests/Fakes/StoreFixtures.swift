import Foundation
@testable import LifelineKit

/// Builds the rows most store tests start from: one session with segments and words.
enum StoreFixtures {
    @discardableResult
    static func session(in repo: SessionRepository, segments texts: [String] = ["the garden had a pomegranate tree"]) throws -> (SessionID, [Segment]) {
        let session = Session(id: .init(), startedAt: .now, endedAt: nil, audioPath: "a.m4a", stageLog: "[]", landingChoiceMade: false)
        try repo.insert(session)
        var out: [Segment] = []
        var cursor = 0
        for (i, text) in texts.enumerated() {
            let words = text.split(separator: " ").map(String.init)
            let seg = Segment(id: .init(), sessionID: session.id, index: i, startMs: cursor, endMs: cursor + words.count * 500, text: text, status: .pending)
            let rows = words.enumerated().map { j, w in
                Word(segmentID: seg.id, index: j, text: w, startMs: cursor + j * 500, endMs: cursor + j * 500 + 400)
            }
            try repo.insert(seg, words: rows)
            out.append(seg)
            cursor += words.count * 500 + 2_000
        }
        return (session.id, out)
    }

    static func candidate(_ segment: SegmentID, ordinal: Int = 0, kind: CandidateKind = .memory, payload: String = "{}", version: String = "v1") -> Candidate {
        Candidate(id: .init(), segmentID: segment, extractorVersion: version, ordinal: ordinal, kind: kind, payload: payload,
                  confidence: 0.9, status: .pending, rejection: nil, createdAt: .now)
    }

    static func memory(from candidate: CandidateID, title: String = "The pomegranate tree") -> Memory {
        Memory(id: .init(), title: title, summaryQuote: "the garden had a pomegranate tree", visibility: .timeline, chapterID: nil,
               createdFromCandidateID: candidate, createdAt: .now)
    }

    /// A kept memory with one span over the whole segment, from a candidate the test does not care about.
    @discardableResult
    static func memory(in repo: MemoryRepository, candidates: CandidateRepository, segment: SegmentID,
                       title: String = "The pomegranate tree", createdAt: Date = .now) throws -> Memory {
        let candidate = Self.candidate(segment)
        try candidates.insert(candidate)
        var memory = Self.memory(from: candidate.id, title: title)
        memory.createdAt = createdAt
        try repo.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment, startMs: 0, endMs: 1000, order: 0)],
                        people: [], places: [], anchors: [])
        return memory
    }
}
