import Foundation

/// What a trim did, so the sheet can take it back while it is open (M6).
public struct TrimReceipt: Sendable, Equatable {
    public var memory: MemoryID
    public var order: Int
    public var before: MemorySpan
    public var after: MemorySpan
    /// The card whose span was rewritten with the trim, and its payload before and after.
    public var candidateID: CandidateID?
    public var payloadBefore: String?
    public var payloadAfter: String?
}

/// "Which part of the recording": the telling's span moves to the words the person chose, within
/// its segment, and the card that made it follows so a later Separate or Keep agrees. Words and
/// audio never change.
extension CandidateActions {
    public func trimTelling(_ memory: MemoryID, order: Int, startWord: Int, endWord: Int) throws -> TrimReceipt {
        guard let span = try store.memories.spans(of: memory).first(where: { $0.order == order }) else { throw Error.targetMissing }
        let words = try store.sessions.words(in: span.segmentID)
        guard startWord >= 0, startWord <= endWord, endWord < words.count else { throw Error.emptySpan }
        var after = span
        after.startMs = words[startWord].startMs
        after.endMs = words[endWord].endMs
        let rewrite = try cardRewrite(for: span, memory: memory, words: words, startWord: startWord, endWord: endWord)
        try store.memories.retime(memory, order: order, startMs: after.startMs, endMs: after.endMs, rewritingCard: rewrite.map { ($0.id, $0.after) })
        return TrimReceipt(memory: memory, order: order, before: span, after: after, candidateID: rewrite?.id, payloadBefore: rewrite?.before, payloadAfter: rewrite?.after)
    }

    /// Refused as stale when the span, or the card, no longer looks like the trim left it.
    public func undoTrim(_ receipt: TrimReceipt) throws {
        guard let current = try store.memories.spans(of: receipt.memory).first(where: { $0.order == receipt.order }), current == receipt.after else { throw Error.stale }
        var rewrite: (id: CandidateID, payload: String)?
        if let card = receipt.candidateID, let before = receipt.payloadBefore {
            guard try store.candidates.fetch(card)?.payload == receipt.payloadAfter else { throw Error.stale }
            rewrite = (card, before)
        }
        try store.memories.retime(receipt.memory, order: receipt.order, startMs: receipt.before.startMs, endMs: receipt.before.endMs, rewritingCard: rewrite)
    }

    /// The card behind a span, and its payload before and after the trim: the memory's own card
    /// for its first telling, the span's card for a later telling, and the telling's card for a
    /// continuation part (its `extra_spans` entry). Nothing is written here.
    private func cardRewrite(for span: MemorySpan, memory: MemoryID, words: [Word], startWord: Int, endWord: Int) throws -> (id: CandidateID, before: String, after: String)? {
        let spans = try store.memories.spans(of: memory)
        let telling = span.continuesOrder.flatMap { order in spans.first { $0.order == order } } ?? span
        let cardID = telling.order == 0 ? try store.memories.fetch(memory)?.createdFromCandidateID : telling.candidateID
        guard let cardID, let card = try store.candidates.fetch(cardID), var out = CandidatePayload.memory(card) else { return nil }
        if span.continuesOrder == nil {
            out.segmentSpan = WordSpan(startWord: startWord, endWord: endWord)
        } else {
            // The part's entry is the one in its segment that covers the words the span covers
            // now: two parts in one segment differ by their words. No entry means the card and
            // the span already disagree, so the trim is refused rather than moving only one.
            guard let oldStart = words.firstIndex(where: { $0.startMs == span.startMs }),
                  let oldEnd = words.lastIndex(where: { $0.endMs == span.endMs }),
                  let i = out.extraSpans.firstIndex(where: { $0.segmentID == span.segmentID.rawValue && $0.startWord == oldStart && $0.endWord == oldEnd })
            else { throw Error.stale }
            out.extraSpans[i].startWord = startWord
            out.extraSpans[i].endWord = endWord
        }
        return (cardID, card.payload, try CandidatePayload.encode(out))
    }
}
