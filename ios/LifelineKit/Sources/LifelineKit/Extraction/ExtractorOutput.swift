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

    /// A moment belongs on the timeline. A fact, a feeling or a goal is placed but never shown on
    /// it and never asked "when?" (M7).
    public var isMoment: Bool { self == .event || self == .other }

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

/// A telling that carried on in another segment after a pause (M5). Written by the app when a
/// continuation arrives, never asked of the model, so it is absent from the schema.
public struct ExtraSpan: Codable, Sendable, Equatable {
    public var segmentID: String
    public var startWord: Int
    public var endWord: Int

    public init(segmentID: String, startWord: Int, endWord: Int) { self.segmentID = segmentID; self.startWord = startWord; self.endWord = endWord }

    enum CodingKeys: String, CodingKey { case segmentID = "segment_id", startWord = "start_word", endWord = "end_word" }
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
    /// Memories from the packet that tell this same moment; several when the archive already holds duplicates (M5).
    public var sameAsMemoryIDs: [String]
    /// A pending card of this session this segment carries on after a pause (M5).
    public var continuesCandidateID: String?
    /// A story id, or a pending card's ref, when this memory is another scene of the same thread (M5).
    public var storyRef: String?
    /// A title for a new story in the person's words, at most 8 words (M5).
    public var storyTitleHint: String?
    public var collectionHint: String?
    public var chapterHint: String?
    public var confidence: Double
    public var extraSpans: [ExtraSpan]
    /// Places, things and ideas this memory names (v6). A place named only in `place_text` reads as a place ref.
    public var entityRefs: [EntityRefOut]
    /// What a fact, feeling or goal is about (v6): an entity id from the packet, a mention's `ref`, or `self`.
    public var aboutRef: String?
    /// The part of life this belongs to, in a word or two (v6).
    public var domainHint: String?

    public var kindOrDefault: MemoryKind { kind ?? .other }
    /// The first named memory, for callers that take one.
    public var sameAsMemoryID: String? { sameAsMemoryIDs.first }

    public init(ref: String, kind: MemoryKind? = nil, title: String, quote: String, segmentSpan: WordSpan, peopleRefs: [String], placeText: String?,
                anchors: [AnchorOut], sameAsMemoryIDs: [String] = [], continuesCandidateID: String? = nil, storyRef: String? = nil,
                storyTitleHint: String? = nil, collectionHint: String?, chapterHint: String?, confidence: Double, extraSpans: [ExtraSpan] = [],
                entityRefs: [EntityRefOut] = [], aboutRef: String? = nil, domainHint: String? = nil) {
        self.ref = ref; self.kind = kind; self.title = title; self.quote = quote; self.segmentSpan = segmentSpan; self.peopleRefs = peopleRefs
        self.placeText = placeText; self.anchors = anchors; self.sameAsMemoryIDs = sameAsMemoryIDs; self.continuesCandidateID = continuesCandidateID
        self.storyRef = storyRef; self.storyTitleHint = storyTitleHint
        self.collectionHint = collectionHint; self.chapterHint = chapterHint; self.confidence = confidence; self.extraSpans = extraSpans
        self.entityRefs = entityRefs; self.aboutRef = aboutRef; self.domainHint = domainHint
    }

    /// The entity refs with `place_text` folded in as a place when no place ref names it.
    public var allEntityRefs: [EntityRefOut] {
        guard let place = placeText?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty,
              !entityRefs.contains(where: { $0.kind == .place && PeopleRepository.normalize($0.text) == PeopleRepository.normalize(place) }) else { return entityRefs }
        return entityRefs + [EntityRefOut(text: place, kind: .place, likelyEntityID: nil)]
    }

    enum CodingKeys: String, CodingKey {
        case ref, kind, title, quote, segmentSpan = "segment_span", peopleRefs = "people_refs", placeText = "place_text", anchors
        case sameAsMemoryID = "same_as_memory_id", sameAsMemoryIDs = "same_as_memory_ids", continuesCandidateID = "continues_candidate_id"
        case storyRef = "story_ref", storyTitleHint = "story_title_hint", collectionHint = "collection_hint", chapterHint = "chapter_hint"
        case confidence, extraSpans = "extra_spans"
        case entityRefs = "entity_refs", aboutRef = "about_ref", domainHint = "domain_hint"
    }

    /// Reads v3/v4 payloads (one `same_as_memory_id`) and v5 ones (a list); the app-written fields default when absent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ref = try c.decode(String.self, forKey: .ref)
        kind = try c.decodeIfPresent(MemoryKind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        quote = try c.decode(String.self, forKey: .quote)
        segmentSpan = try c.decode(WordSpan.self, forKey: .segmentSpan)
        peopleRefs = try c.decode([String].self, forKey: .peopleRefs)
        placeText = try c.decodeIfPresent(String.self, forKey: .placeText)
        anchors = try c.decode([AnchorOut].self, forKey: .anchors)
        if let list = try c.decodeIfPresent([String].self, forKey: .sameAsMemoryIDs) {
            sameAsMemoryIDs = list
        } else {
            sameAsMemoryIDs = (try c.decodeIfPresent(String.self, forKey: .sameAsMemoryID)).map { [$0] } ?? []
        }
        continuesCandidateID = try c.decodeIfPresent(String.self, forKey: .continuesCandidateID)
        storyRef = try c.decodeIfPresent(String.self, forKey: .storyRef)
        storyTitleHint = try c.decodeIfPresent(String.self, forKey: .storyTitleHint)
        collectionHint = try c.decodeIfPresent(String.self, forKey: .collectionHint)
        chapterHint = try c.decodeIfPresent(String.self, forKey: .chapterHint)
        confidence = try c.decode(Double.self, forKey: .confidence)
        extraSpans = try c.decodeIfPresent([ExtraSpan].self, forKey: .extraSpans) ?? []
        entityRefs = try c.decodeIfPresent([EntityRefOut].self, forKey: .entityRefs) ?? []
        aboutRef = try c.decodeNonEmpty(forKey: .aboutRef)
        domainHint = try c.decodeNonEmpty(forKey: .domainHint)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ref, forKey: .ref)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(quote, forKey: .quote)
        try c.encode(segmentSpan, forKey: .segmentSpan)
        try c.encode(peopleRefs, forKey: .peopleRefs)
        try c.encode(placeText, forKey: .placeText)
        try c.encode(anchors, forKey: .anchors)
        try c.encode(sameAsMemoryIDs, forKey: .sameAsMemoryIDs)
        try c.encode(continuesCandidateID, forKey: .continuesCandidateID)
        try c.encode(storyRef, forKey: .storyRef)
        try c.encode(storyTitleHint, forKey: .storyTitleHint)
        try c.encode(collectionHint, forKey: .collectionHint)
        try c.encode(chapterHint, forKey: .chapterHint)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(extraSpans, forKey: .extraSpans)
        try c.encode(entityRefs, forKey: .entityRefs)
        try c.encode(aboutRef, forKey: .aboutRef)
        try c.encode(domainHint, forKey: .domainHint)
    }
}

/// A place, thing or idea a memory names (v6).
public struct EntityRefOut: Codable, Sendable, Equatable {
    public var text: String
    public var kind: MentionKind
    public var likelyEntityID: String?

    public init(text: String, kind: MentionKind, likelyEntityID: String?) { self.text = text; self.kind = kind; self.likelyEntityID = likelyEntityID }

    enum CodingKeys: String, CodingKey { case text, kind, likelyEntityID = "likely_entity_id" }
}

public enum MentionKind: String, Codable, Sendable, CaseIterable {
    case person, place, thing, idea

    public var entityType: EntityType {
        switch self {
        case .person: .person
        case .place: .place
        case .thing: .thing
        case .idea: .idea
        }
    }
}

public struct MentionOut: Codable, Sendable, Equatable {
    public var text: String
    public var kind: MentionKind
    public var likelyAliasOfPersonID: String?
    public var confidence: Double
    /// The owner's kin or role phrase for a person ("my mom", "my best friend"), or nil.
    public var relationText: String?
    /// A handle a memory's `about_ref` can point at (v6).
    public var ref: String?
    /// An entity on file this names, from the packet (v6).
    public var likelyEntityID: String?
    /// An idea's title: the person's own words, at most 8, or nil (v6). Never composed.
    public var title: String?
    public var domainHint: String?

    public init(text: String, kind: MentionKind, likelyAliasOfPersonID: String?, confidence: Double, relationText: String? = nil,
                ref: String? = nil, likelyEntityID: String? = nil, title: String? = nil, domainHint: String? = nil) {
        self.text = text; self.kind = kind; self.likelyAliasOfPersonID = likelyAliasOfPersonID; self.confidence = confidence
        self.relationText = relationText; self.ref = ref; self.likelyEntityID = likelyEntityID; self.title = title; self.domainHint = domainHint
    }

    enum CodingKeys: String, CodingKey {
        case text, kind, likelyAliasOfPersonID = "likely_alias_of_person_id", confidence, relationText = "relation_text"
        case ref, likelyEntityID = "likely_entity_id", title, domainHint = "domain_hint"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        kind = try c.decode(MentionKind.self, forKey: .kind)
        likelyAliasOfPersonID = try c.decodeIfPresent(String.self, forKey: .likelyAliasOfPersonID)
        confidence = try c.decode(Double.self, forKey: .confidence)
        relationText = try c.decodeIfPresent(String.self, forKey: .relationText)
        ref = try c.decodeNonEmpty(forKey: .ref)
        likelyEntityID = try c.decodeIfPresent(String.self, forKey: .likelyEntityID)
        title = try c.decodeNonEmpty(forKey: .title)
        domainHint = try c.decodeNonEmpty(forKey: .domainHint)
    }
}

extension KeyedDecodingContainer {
    /// A string the schema sends as "" when there is none (see `ExtractorSchema`): absent, null,
    /// empty and whitespace all read as nil.
    func decodeNonEmpty(forKey key: Key) throws -> String? {
        guard let text = try decodeIfPresent(String.self, forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
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
