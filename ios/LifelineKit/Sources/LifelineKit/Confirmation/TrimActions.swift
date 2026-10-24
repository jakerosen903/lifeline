import Foundation

/// What a trim did, so the sheet can take it back while it is open (M6).
public struct TrimReceipt: Sendable, Equatable {
    public var memory: MemoryID
    public var order: Int
    public var before: MemorySpan
    public var after: MemorySpan
    /// The card whose span was rewritten with the trim, and its payload before.
    public var candidateID: CandidateID?
    public var payloadBefore: String?
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
        let (card, payloadBefore) = try rewriteCard(for: span, memory: memory, startWord: startWord, endWord: endWord)
        try store.memories.retime(memory, order: order, startMs: after.startMs, endMs: after.endMs)
        return TrimReceipt(memory: memory, order: order, before: span, after: after, candidateID: card, payloadBefore: payloadBefore)
    }

    /// Refused as stale when the span no longer looks like the trim left it.
    public func undoTrim(_ receipt: TrimReceipt) throws {
        guard let current = try store.memories.spans(of: receipt.memory).first(where: { $0.order == receipt.order }), current == receipt.after else { throw Error.stale }
        if let card = receipt.candidateID, let payload = receipt.payloadBefore { try store.candidates.updatePayload(card, payload) }
        try store.memories.retime(receipt.memory, order: receipt.order, startMs: receipt.before.startMs, endMs: receipt.before.endMs)
    }

    /// The card behind a span: the memory's own card for its first telling, the span's card for a
    /// later telling, and the telling's card for a continuation part (its `extra_spans` entry).
    private func rewriteCard(for span: MemorySpan, memory: MemoryID, startWord: Int, endWord: Int) throws -> (CandidateID?, String?) {
        let spans = try store.memories.spans(of: memory)
        let telling = span.continuesOrder.flatMap { order in spans.first { $0.order == order } } ?? span
        let cardID = telling.order == 0 ? try store.memories.fetch(memory)?.createdFromCandidateID : telling.candidateID
        guard let cardID, let card = try store.candidates.fetch(cardID), var out = CandidatePayload.memory(card) else { return (nil, nil) }
        let before = card.payload
        if span.continuesOrder == nil {
            out.segmentSpan = WordSpan(startWord: startWord, endWord: endWord)
        } else if let i = out.extraSpans.firstIndex(where: { $0.segmentID == span.segmentID.rawValue }) {
            out.extraSpans[i].startWord = startWord
            out.extraSpans[i].endWord = endWord
        }
        try store.candidates.updatePayload(cardID, try CandidatePayload.encode(out))
        return (cardID, before)
    }
}
