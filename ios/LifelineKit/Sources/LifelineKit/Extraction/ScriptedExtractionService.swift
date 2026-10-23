import Foundation

/// Deterministic candidates for UI tests and demos, matched to `ScriptedVoiceSession.sampleScript`:
/// the blue-door segment yields a memory anchored by an age and by "before Maya climbed it";
/// the Maya segment yields a memory stated "in 1998" and an unknown-person mention; everything
/// else yields nothing.
public struct ScriptedExtractionService: ExtractionService {
    public let version = "scripted"
    public var delayMs: Int
    /// UI tests of the heavy path: the Maya segment is flagged as narration of past harm.
    public var heavy: Bool

    public init(delayMs: Int = 300, heavy: Bool = false) { self.delayMs = delayMs; self.heavy = heavy }

    public func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse {
        try? await Task.sleep(for: .milliseconds(delayMs))
        let words = request.words
        let text = request.segmentText
        var memories: [MemoryOut] = []
        var mentions: [MentionOut] = []
        if text.localizedCaseInsensitiveContains("blue door") {
            // A second telling names the earlier memory when the packet carries one (M4.1 "Same as X?").
            let earlier = request.packet.memories.first { $0.title == "The blue door" }?.id
            memories.append(MemoryOut(ref: "m1", kind: .event, title: "The blue door", quote: text,
                                      segmentSpan: WordSpan(startWord: 0, endWord: max(0, words.count - 1)),
                                      peopleRefs: [], placeText: nil,
                                      anchors: [AnchorOut(phrase: "when I was six", relation: .age, targetText: nil, value: nil),
                                                AnchorOut(phrase: "before Maya climbed it", relation: .before, targetText: "Maya climbed it", value: nil)],
                                      sameAsMemoryID: earlier, collectionHint: nil, chapterHint: nil, confidence: 0.9))
        }
        if text.localizedCaseInsensitiveContains("climbed it in 1998") {
            memories.append(MemoryOut(ref: "m2", kind: .event, title: "Maya climbed it", quote: text,
                                      segmentSpan: WordSpan(startWord: 0, endWord: max(0, words.count - 1)),
                                      peopleRefs: ["Maya"], placeText: nil,
                                      anchors: [AnchorOut(phrase: "in 1998", relation: .absolute, targetText: nil, value: nil)],
                                      sameAsMemoryID: nil, collectionHint: "every summer", chapterHint: nil, confidence: 0.8))
        }
        if words.contains(where: { $0.caseInsensitiveCompare("Maya") == .orderedSame }) {
            mentions.append(MentionOut(text: "Maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8, relationText: "my sister"))
        }
        let empty = Usage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
        var flags = Flags.none
        if heavy, text.localizedCaseInsensitiveContains("climbed it in 1998") { flags.disclosure = .past }
        return ExtractionResponse(output: ExtractorOutput(memories: memories, mentions: mentions, flags: flags),
                                  version: version, model: "scripted", usage: empty)
    }
}
