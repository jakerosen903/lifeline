import Foundation

/// The extractor's structured output, exactly the schema in the design spec (§7).
/// Coding keys are the wire names; every field is present in the JSON, optional ones as null.
public struct ExtractorOutput: Codable, Sendable, Equatable {
    public var memories: [MemoryOut]
    public var mentions: [MentionOut]
    public var flags: Flags

    public init(memories: [MemoryOut], mentions: [MentionOut], flags: Flags) {
        self.memories = memories; self.mentions = mentions; self.flags = flags
    }

    public static func decode(from data: Data) throws -> ExtractorOutput {
        try JSONDecoder().decode(ExtractorOutput.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Inclusive word indexes into the segment's words.
public struct WordSpan: Codable, Sendable, Equatable {
    public var startWord: Int
    public var endWord: Int

    public init(startWord: Int, endWord: Int) { self.startWord = startWord; self.endWord = endWord }

    enum CodingKeys: String, CodingKey { case startWord = "start_word", endWord = "end_word" }
}

public struct AnchorOut: Codable, Sendable, Equatable {
    public var phrase: String
    public var relation: AnchorRelation
    public var targetText: String?
    public var value: String?

    public init(phrase: String, relation: AnchorRelation, targetText: String?, value: String?) {
        self.phrase = phrase; self.relation = relation; self.targetText = targetText; self.value = value
    }

    enum CodingKeys: String, CodingKey { case phrase, relation, targetText = "target_text", value }
}

public struct MemoryOut: Codable, Sendable, Equatable {
    public var ref: String
    public var title: String
    public var quote: String
    public var segmentSpan: WordSpan
    public var peopleRefs: [String]
    public var placeText: String?
    public var anchors: [AnchorOut]
    public var sameAsMemoryID: String?
    public var collectionHint: String?
    public var chapterHint: String?
    public var confidence: Double

    public init(ref: String, title: String, quote: String, segmentSpan: WordSpan, peopleRefs: [String], placeText: String?,
                anchors: [AnchorOut], sameAsMemoryID: String?, collectionHint: String?, chapterHint: String?, confidence: Double) {
        self.ref = ref; self.title = title; self.quote = quote; self.segmentSpan = segmentSpan; self.peopleRefs = peopleRefs
        self.placeText = placeText; self.anchors = anchors; self.sameAsMemoryID = sameAsMemoryID
        self.collectionHint = collectionHint; self.chapterHint = chapterHint; self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case ref, title, quote, segmentSpan = "segment_span", peopleRefs = "people_refs", placeText = "place_text", anchors
        case sameAsMemoryID = "same_as_memory_id", collectionHint = "collection_hint", chapterHint = "chapter_hint", confidence
    }
}

public enum MentionKind: String, Codable, Sendable, CaseIterable {
    case person, place
}

public struct MentionOut: Codable, Sendable, Equatable {
    public var text: String
    public var kind: MentionKind
    public var likelyAliasOfPersonID: String?
    public var confidence: Double

    public init(text: String, kind: MentionKind, likelyAliasOfPersonID: String?, confidence: Double) {
        self.text = text; self.kind = kind; self.likelyAliasOfPersonID = likelyAliasOfPersonID; self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey { case text, kind, likelyAliasOfPersonID = "likely_alias_of_person_id", confidence }
}

public struct Flags: Codable, Sendable, Equatable {
    public var seriousDisclosure: Bool
    public var wantsToStop: Bool
    public var wantsToChangeSubject: Bool

    public init(seriousDisclosure: Bool, wantsToStop: Bool, wantsToChangeSubject: Bool) {
        self.seriousDisclosure = seriousDisclosure; self.wantsToStop = wantsToStop; self.wantsToChangeSubject = wantsToChangeSubject
    }

    public static let none = Flags(seriousDisclosure: false, wantsToStop: false, wantsToChangeSubject: false)
    public var isAnySet: Bool { seriousDisclosure || wantsToStop || wantsToChangeSubject }

    enum CodingKeys: String, CodingKey {
        case seriousDisclosure = "serious_disclosure", wantsToStop = "wants_to_stop", wantsToChangeSubject = "wants_to_change_subject"
    }
}
