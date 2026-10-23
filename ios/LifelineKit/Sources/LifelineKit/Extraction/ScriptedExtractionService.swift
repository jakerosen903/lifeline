import Foundation

/// Deterministic candidates for UI tests and demos, matched to `ScriptedVoiceSession.sampleScript`:
/// a segment that mentions a blue door yields one memory; a segment that names Maya yields one
/// unknown-person mention; everything else yields nothing.
public struct ScriptedExtractionService: ExtractionService {
    public let version = "scripted"
    public var delayMs: Int

    public init(delayMs: Int = 300) { self.delayMs = delayMs }

    public func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse {
        try? await Task.sleep(for: .milliseconds(delayMs))
        let words = request.words
        var memories: [MemoryOut] = []
        var mentions: [MentionOut] = []
        if request.segmentText.localizedCaseInsensitiveContains("blue door") {
            memories.append(MemoryOut(ref: "m1", title: "The blue door", quote: request.segmentText,
                                      segmentSpan: WordSpan(startWord: 0, endWord: max(0, words.count - 1)),
                                      peopleRefs: [], placeText: nil,
                                      anchors: [AnchorOut(phrase: "blue door", relation: .during, targetText: nil, value: nil)],
                                      sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9))
        }
        if words.contains(where: { $0.caseInsensitiveCompare("Maya") == .orderedSame }) {
            mentions.append(MentionOut(text: "Maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8))
        }
        let empty = Usage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
        return ExtractionResponse(output: ExtractorOutput(memories: memories, mentions: mentions, flags: .none),
                                  version: version, model: "scripted", usage: empty)
    }
}
