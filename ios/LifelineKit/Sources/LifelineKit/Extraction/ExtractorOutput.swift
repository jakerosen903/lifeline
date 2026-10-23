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

/// What sort of thing a memory candidate is. The first seam of the later kinds/domains
/// taxonomy: it lives in the payload, not in a column, and only changes the card's words.
public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case event, fact, feeling, goal, other

    /// The card heading. Only an event is called a memory.
    public var cardLabel: String {
        switch self {
        case .event, .other: "Sounds like a memory"
        case .fact: "Something about your life"
        case .feeling: "Something you felt"
        case .goal: "Something you wanted"
        }
    }
}

public struct MemoryOut: Codable, Sendable, Equatable {
    public var ref: String
    /// nil only for payloads written by extractor v1, which had no kinds.
    public var kind: MemoryKind?
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

    public var kindOrDefault: MemoryKind { kind ?? .other }

    public init(ref: String, kind: MemoryKind? = nil, title: String, quote: String, segmentSpan: WordSpan, peopleRefs: [String], placeText: String?,
                anchors: [AnchorOut], sameAsMemoryID: String?, collectionHint: String?, chapterHint: String?, confidence: Double) {
        self.ref = ref; self.kind = kind; self.title = title; self.quote = quote; self.segmentSpan = segmentSpan; self.peopleRefs = peopleRefs
        self.placeText = placeText; self.anchors = anchors; self.sameAsMemoryID = sameAsMemoryID
        self.collectionHint = collectionHint; self.chapterHint = chapterHint; self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case ref, kind, title, quote, segmentSpan = "segment_span", peopleRefs = "people_refs", placeText = "place_text", anchors
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
    /// The owner's kin or role phrase for a person ("my mom", "my best friend"), or nil.
    public var relationText: String?

    public init(text: String, kind: MentionKind, likelyAliasOfPersonID: String?, confidence: Double, relationText: String? = nil) {
        self.text = text; self.kind = kind; self.likelyAliasOfPersonID = likelyAliasOfPersonID; self.confidence = confidence
        self.relationText = relationText
    }

    enum CodingKeys: String, CodingKey {
        case text, kind, likelyAliasOfPersonID = "likely_alias_of_person_id", confidence, relationText = "relation_text"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        kind = try c.decode(MentionKind.self, forKey: .kind)
        likelyAliasOfPersonID = try c.decodeIfPresent(String.self, forKey: .likelyAliasOfPersonID)
        confidence = try c.decode(Double.self, forKey: .confidence)
        relationText = try c.decodeIfPresent(String.self, forKey: .relationText)
    }
}

/// A disclosure of harm. Narration of the past and danger now call for the same fixed words but
/// a different landing; one broad flag was too coarse to shape the whole experience.
public enum DisclosureKind: String, Codable, Sendable, CaseIterable {
    case none, past, present
}

public struct Flags: Codable, Sendable, Equatable {
    public var disclosure: DisclosureKind
    public var wantsToStop: Bool
    public var wantsToChangeSubject: Bool

    public init(disclosure: DisclosureKind, wantsToStop: Bool, wantsToChangeSubject: Bool) {
        self.disclosure = disclosure; self.wantsToStop = wantsToStop; self.wantsToChangeSubject = wantsToChangeSubject
    }

    /// Extractor v2 rows and older call sites: a serious disclosure reads as narration of the past.
    public init(seriousDisclosure: Bool, wantsToStop: Bool, wantsToChangeSubject: Bool) {
        self.init(disclosure: seriousDisclosure ? .past : .none, wantsToStop: wantsToStop, wantsToChangeSubject: wantsToChangeSubject)
    }

    public static let none = Flags(disclosure: .none, wantsToStop: false, wantsToChangeSubject: false)
    public var seriousDisclosure: Bool { disclosure != .none }
    /// Winds the session down and suppresses every organizational prompt.
    public var isHeavy: Bool { disclosure != .none || wantsToStop }
    public var isAnySet: Bool { disclosure != .none || wantsToStop || wantsToChangeSubject }

    enum CodingKeys: String, CodingKey {
        case disclosure, seriousDisclosure = "serious_disclosure", wantsToStop = "wants_to_stop", wantsToChangeSubject = "wants_to_change_subject"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let kind = try c.decodeIfPresent(DisclosureKind.self, forKey: .disclosure) {
            disclosure = kind
        } else {
            disclosure = try c.decodeIfPresent(Bool.self, forKey: .seriousDisclosure) == true ? .past : .none
        }
        wantsToStop = try c.decodeIfPresent(Bool.self, forKey: .wantsToStop) ?? false
        wantsToChangeSubject = try c.decodeIfPresent(Bool.self, forKey: .wantsToChangeSubject) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(disclosure, forKey: .disclosure)
        try c.encode(wantsToStop, forKey: .wantsToStop)
        try c.encode(wantsToChangeSubject, forKey: .wantsToChangeSubject)
    }
}
