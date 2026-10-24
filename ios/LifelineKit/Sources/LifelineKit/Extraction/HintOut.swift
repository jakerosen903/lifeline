import Foundation

public enum HintKind: String, Codable, Sendable {
    case collection, chapter, story
}

/// "Sounds like it belongs here": a collection or chapter phrase the extractor heard in a memory.
/// The hint waits for its memory to be accepted; its payload names that memory's candidate.
public struct HintOut: Codable, Sendable, Equatable {
    public var kind: HintKind
    public var phrase: String
    public var memoryCandidateID: String

    public init(kind: HintKind, phrase: String, memoryCandidateID: String) {
        self.kind = kind; self.phrase = phrase; self.memoryCandidateID = memoryCandidateID
    }

    enum CodingKeys: String, CodingKey { case kind, phrase, memoryCandidateID = "memory_candidate_id" }
}
