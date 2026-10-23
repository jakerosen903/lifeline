import Foundation

/// What a merge did, enough to take it back exactly (M4.1).
public struct MergeReceipt: Sendable, Equatable {
    public var target: MemoryID
    public var targetTitle: String
    /// The target as it was, then the source memory when one was folded in.
    public var before: [MemoryRepository.Snapshot]
    /// The card, when the merge was "Same story" on a card.
    public var candidateID: CandidateID?
    public var mergedAt: Date
}

/// "Same story" on a card, "Same as another memory…" on the Change sheet, and undo. Nothing
/// here runs without a tap; Keep stays the default.
extension CandidateActions {
    public struct MergedCandidate: Sendable, Equatable {
        public var receipt: MergeReceipt
        public var newMentions: [Mention]
    }

    /// The card becomes a later telling of `target`: a span, the card's people, place and
    /// anchors, no new memory. A stand-in target becomes real, with this telling as its first.
    public func mergeCandidate(_ candidate: Candidate, into target: MemoryID) throws -> MergedCandidate {
        guard candidate.kind == .memory else { throw Error.wrongKind }
        try requirePending(candidate)
        guard let out = CandidatePayload.memory(candidate) else { throw Error.badPayload }
        guard let targetMemory = try store.memories.fetch(target), let before = try store.memories.snapshot(of: target) else { throw Error.targetMissing }
        let words = try store.sessions.words(in: candidate.segmentID)
        guard !words.isEmpty, out.segmentSpan.startWord >= 0, out.segmentSpan.endWord < words.count,
              out.segmentSpan.startWord <= out.segmentSpan.endWord else { throw Error.emptySpan }

        var span = MemorySpan(memoryID: target, segmentID: candidate.segmentID,
                              startMs: words[out.segmentSpan.startWord].startMs, endMs: words[out.segmentSpan.endWord].endMs,
                              order: try store.memories.nextSpanOrder(of: target), titleText: out.title, candidateID: candidate.id)
        if targetMemory.isFloating {
            // The owner named this moment before telling it; now they have told it.
            try store.memories.deleteSpans(of: target)
            span.order = 0
            try store.memories.updateFields(target, title: out.title, summaryQuote: out.quote, createdFromCandidateID: candidate.id)
        }
        try store.memories.insertSpan(span)
        let edges = try edges(of: out, for: target)
        for person in edges.people { try store.memories.link(person.personID, to: target, roleText: person.roleText) }
        for place in edges.places { try store.memories.insertPlace(place) }
        for anchor in edges.anchors { try store.memories.insertAnchor(anchor) }
        try store.candidates.setStatus(candidate.id, .accepted)
        let newMentions = try finishEdges(edges, segment: candidate.segmentID)
        try reindex(target)
        _ = try ResolverRunner(store: store).run()
        return MergedCandidate(receipt: MergeReceipt(target: target, targetTitle: targetMemory.title, before: [before], candidateID: candidate.id, mergedAt: .now),
                               newMentions: newMentions)
    }

    /// One memory becomes later tellings of another. The target keeps its title, range (unless
    /// it had none), collections and chapter (unless it had none).
    public func merge(_ source: MemoryID, into target: MemoryID) throws -> MergeReceipt {
        guard source != target else { throw Error.sameMemory }
        guard let targetMemory = try store.memories.fetch(target), let sourceMemory = try store.memories.fetch(source),
              let targetBefore = try store.memories.snapshot(of: target), let sourceBefore = try store.memories.snapshot(of: source) else { throw Error.targetMissing }
        try store.memories.fold(source, into: target, sourceTitle: sourceMemory.title, sourceCandidate: sourceMemory.createdFromCandidateID)
        if !targetMemory.range.isPlaced, sourceMemory.range.isPlaced {
            try store.memories.updateRange(target, sourceMemory.range)
        }
        try reindex(target)
        if let chapter = try store.memories.fetch(target)?.chapterID { try chapterRangeFromMembers(chapter) }
        _ = try ResolverRunner(store: store).run()
        return MergeReceipt(target: target, targetTitle: targetMemory.title, before: [targetBefore, sourceBefore], candidateID: nil, mergedAt: .now)
    }

    /// Puts both sides back. Refused when the target changed since the merge, so a stale
    /// receipt never overwrites later work.
    public func unmerge(_ receipt: MergeReceipt) throws {
        guard let targetBefore = receipt.before.first else { throw Error.stale }
        let current = try store.memories.spans(of: receipt.target).count
        let added = receipt.candidateID != nil ? 1 : receipt.before.dropFirst().reduce(0) { $0 + $1.spans.count }
        let expected = targetBefore.memory.isFloating && receipt.candidateID != nil ? 1 : targetBefore.spans.count + added
        guard current == expected else { throw Error.stale }
        for snapshot in receipt.before { try store.memories.restore(snapshot) }
        if let candidate = receipt.candidateID { try store.candidates.setStatus(candidate, .pending) }
        for snapshot in receipt.before { try reindex(snapshot.memory.id) }
        _ = try ResolverRunner(store: store).run()
    }
}
