import Foundation

/// How a candidate's `payload` column is written and read back: sorted-key JSON of the
/// extractor object, so two runs with the same output produce the same bytes.
public enum CandidatePayload {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from payload: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(payload.utf8))
    }

    public static func memory(_ candidate: Candidate) -> MemoryOut? {
        guard candidate.kind == .memory else { return nil }
        return try? decode(MemoryOut.self, from: candidate.payload)
    }

    public static func hint(_ candidate: Candidate) -> HintOut? {
        guard candidate.kind == .hint else { return nil }
        return try? decode(HintOut.self, from: candidate.payload)
    }

    public static func mention(_ candidate: Candidate) -> MentionOut? {
        guard candidate.kind == .person || candidate.kind == .place || candidate.kind == .entity else { return nil }
        return try? decode(MentionOut.self, from: candidate.payload)
    }
}
