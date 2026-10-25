import Foundation

/// Deterministic candidates for UI tests and demos, matched to `ScriptedVoiceSession.sampleScript`:
/// the blue-door segment yields a memory anchored by an age and by "before Maya climbed it";
/// the Maya segment yields a memory stated "in 1998" and an unknown-person mention; everything
/// the third line continues the Maya card when it is pending; everything else yields nothing.
public struct ScriptedExtractionService: ExtractionService {
    public let version = "scripted"
    public var delayMs: Int
    /// UI tests of the heavy path: the Maya segment is flagged as narration of past harm.
    public var heavy: Bool
    /// UI tests of kinds (M7): the blue-door segment is a fact, "The house had a blue door".
    public var facts: Bool
    /// UI tests of entities (M7), matched to `ScriptedVoiceSession.entityScript`.
    public var entities: Bool

    /// The one story the script tells: both scenes carry this ref, the Maya scene carries the title hint.
    public static let storyRef = "story-scripted"

    public init(delayMs: Int = 300, heavy: Bool = false, facts: Bool = false, entities: Bool = false) {
        self.delayMs = delayMs; self.heavy = heavy; self.facts = facts; self.entities = entities
    }

    public func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse {
        try? await Task.sleep(for: .milliseconds(delayMs))
        let words = request.words
        let text = request.segmentText
        if entities { return Self.response(Self.entityOutput(text: text, words: words)) }
        var memories: [MemoryOut] = []
        var mentions: [MentionOut] = []
        if text.localizedCaseInsensitiveContains("blue door") {
            // A second telling names the earlier memory when the packet carries one (M4.1 "Same as X?").
            let earlier = request.packet.memories.filter { $0.title == "The blue door" }.map(\.id)
            memories.append(MemoryOut(ref: "m1", kind: facts ? .fact : .event, title: facts ? "The house had a blue door" : "The blue door", quote: text,
                                      segmentSpan: WordSpan(startWord: 0, endWord: max(0, words.count - 1)),
                                      peopleRefs: [], placeText: nil,
                                      anchors: [AnchorOut(phrase: "when I was six", relation: .age, targetText: nil, value: nil),
                                                AnchorOut(phrase: "before Maya climbed it", relation: .before, targetText: "Maya climbed it", value: nil)],
                                      sameAsMemoryIDs: earlier, storyRef: Self.storyRef, collectionHint: nil, chapterHint: nil, confidence: 0.9))
        }
        if text.localizedCaseInsensitiveContains("climbed it in 1998") {
            memories.append(MemoryOut(ref: "m2", kind: .event, title: "Maya climbed it", quote: text,
                                      segmentSpan: WordSpan(startWord: 0, endWord: max(0, words.count - 1)),
                                      peopleRefs: ["Maya"], placeText: nil,
                                      anchors: [AnchorOut(phrase: "in 1998", relation: .absolute, targetText: nil, value: nil)],
                                      storyRef: Self.storyRef, storyTitleHint: "The blue door summer",
                                      collectionHint: "every summer", chapterHint: nil, confidence: 0.8))
        }
        // The third line carries on the Maya telling after a pause when its card is still pending (M5).
        if text.localizedCaseInsensitiveContains("the year before she was born"),
           let maya = request.packet.pending.first(where: { $0.title == "Maya climbed it" }) {
            memories.append(MemoryOut(ref: "m3", kind: .event, title: "Maya climbed it", quote: text,
                                      segmentSpan: WordSpan(startWord: 0, endWord: max(0, words.count - 1)),
                                      peopleRefs: [], placeText: nil, anchors: [], continuesCandidateID: maya.candidateID,
                                      collectionHint: nil, chapterHint: nil, confidence: 0.8))
        }
        // Fact mode (M7): the blue door is a detail of the thing "the house", at home.
        if facts, text.localizedCaseInsensitiveContains("blue door"), let i = memories.firstIndex(where: { $0.ref == "m1" }) {
            let known = request.packet.entities.first { $0.type == EntityType.thing.rawValue && PeopleRepository.normalize($0.title) == "the house" }
            memories[i].aboutRef = known?.id ?? "t1"
            memories[i].domainHint = "home"
            if known == nil {
                mentions.append(MentionOut(text: "the house", kind: .thing, likelyAliasOfPersonID: nil, confidence: 0.8, ref: "t1", domainHint: "home"))
            }
        }
        if words.contains(where: { $0.caseInsensitiveCompare("Maya") == .orderedSame }) {
            mentions.append(MentionOut(text: "Maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8, relationText: "my sister"))
        }
        var flags = Flags.none
        if heavy, text.localizedCaseInsensitiveContains("climbed it in 1998") { flags.disclosure = .past }
        return Self.response(ExtractorOutput(memories: memories, mentions: mentions, flags: flags))
    }

    private static func response(_ output: ExtractorOutput) -> ExtractionResponse {
        ExtractionResponse(output: output, version: "scripted", model: "scripted",
                           usage: Usage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0))
    }

    /// The entity script (M7): the blue door is a fact about the house (home); painting it is a
    /// moment in 1995; "hard work" is an idea named by two moments years apart; the shed is a
    /// thing no memory carries, so it gets a card of its own.
    static func entityOutput(text: String, words: [String]) -> ExtractorOutput {
        let all = WordSpan(startWord: 0, endWord: max(0, words.count - 1))
        func memory(_ ref: String, _ kind: MemoryKind, _ title: String, anchors: [AnchorOut] = [], refs: [EntityRefOut] = [], about: String? = nil, domain: String? = nil) -> MemoryOut {
            MemoryOut(ref: ref, kind: kind, title: title, quote: text, segmentSpan: all, peopleRefs: [], placeText: nil, anchors: anchors,
                      collectionHint: nil, chapterHint: nil, confidence: 0.9, entityRefs: refs, aboutRef: about, domainHint: domain)
        }
        let house = EntityRefOut(text: "the house", kind: .thing, likelyEntityID: nil)
        let hardWork = EntityRefOut(text: "hard work", kind: .idea, likelyEntityID: nil)
        var memories: [MemoryOut] = []
        var mentions: [MentionOut] = []
        if text.contains("blue door") {
            memories.append(memory("m1", .fact, "The house had a blue door", about: "t1"))
            mentions.append(MentionOut(text: "the house", kind: .thing, likelyAliasOfPersonID: nil, confidence: 0.8, ref: "t1", domainHint: "home"))
        } else if text.contains("painted the house") {
            memories.append(memory("m2", .event, "We painted the house", anchors: [AnchorOut(phrase: "in 1995", relation: .absolute, targetText: nil, value: nil)], refs: [house]))
        } else if text.contains("hard work was everything") {
            memories.append(memory("m3", .event, "Hard work was everything", anchors: [AnchorOut(phrase: "in 1990", relation: .absolute, targetText: nil, value: nil)], refs: [hardWork]))
        } else if text.contains("hard work differently") {
            memories.append(memory("m4", .event, "I saw hard work differently", anchors: [AnchorOut(phrase: "in 2020", relation: .absolute, targetText: nil, value: nil)], refs: [hardWork]))
        } else if text.contains("old shed") {
            mentions.append(MentionOut(text: "the old shed", kind: .thing, likelyAliasOfPersonID: nil, confidence: 0.8, ref: "t2"))
        }
        return ExtractorOutput(memories: memories, mentions: mentions, flags: .none)
    }
}
