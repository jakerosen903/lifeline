import Foundation

/// Loads a transcript JSON file as a finished session. Used by the CLI and by fixtures.
///
/// Format:
/// ```
/// { "started_at": ISO-8601, "segments": [ { "start_ms", "end_ms", "words": [ { "text", "start_ms", "end_ms" } ] } ] }
/// ```
/// Segment text is the words joined by single spaces. Every segment is stored `pending`.
public enum TranscriptImport {
    public enum Error: Swift.Error, Equatable {
        case wordOutsideSegment(segment: Int, word: String)
        case segmentsOutOfOrder(segment: Int)
        case emptySegment(segment: Int)
    }

    struct File: Decodable {
        let startedAt: Date
        let segments: [SegmentJSON]
    }

    struct SegmentJSON: Decodable {
        let startMs: Int
        let endMs: Int
        let words: [WordJSON]
    }

    struct WordJSON: Decodable {
        let text: String
        let startMs: Int
        let endMs: Int
    }

    @discardableResult
    public static func importTranscript(at url: URL, into repo: SessionRepository, audioPath: String = "") throws -> SessionID {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: try Data(contentsOf: url))
        try validate(file)

        let id = SessionID()
        let lastEnd = file.segments.last?.endMs ?? 0
        let session = Session(id: id, startedAt: file.startedAt,
                              endedAt: file.startedAt.addingTimeInterval(Double(lastEnd) / 1_000),
                              audioPath: audioPath, stageLog: "[]", landingChoiceMade: false)
        try repo.insert(session)
        do {
            for (index, s) in file.segments.enumerated() {
                let segment = Segment(id: .init(), sessionID: id, index: index, startMs: s.startMs, endMs: s.endMs,
                                      text: s.words.map(\.text).joined(separator: " "), status: .pending)
                let words = s.words.enumerated().map { i, w in
                    Word(segmentID: segment.id, index: i, text: w.text, startMs: w.startMs, endMs: w.endMs)
                }
                try repo.insert(segment, words: words)
            }
        } catch {
            try? repo.delete(id)
            throw error
        }
        return id
    }

    private static func validate(_ file: File) throws {
        var previousEnd = Int.min
        for (i, s) in file.segments.enumerated() {
            guard !s.words.isEmpty else { throw Error.emptySegment(segment: i) }
            guard s.startMs >= previousEnd else { throw Error.segmentsOutOfOrder(segment: i) }
            previousEnd = s.endMs
            let range = MsRange(start: s.startMs, end: s.endMs)
            for w in s.words where !range.contains(w.startMs) || w.endMs > s.endMs {
                throw Error.wordOutsideSegment(segment: i, word: w.text)
            }
        }
    }
}
