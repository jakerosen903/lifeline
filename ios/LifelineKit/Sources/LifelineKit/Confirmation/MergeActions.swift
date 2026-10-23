import Foundation

/// What a merge did, enough to take it back exactly (M4.1).
public struct MergeReceipt: Sendable, Equatable {
    public var target: MemoryID
    public var targetTitle: String
    /// The target as it was, then the source memory when one was folded in.
    public var before: [MemoryRepository.Snapshot]
    /// The target right after the merge. Undo is refused when the target no longer looks like this.
    public var after: MemoryRepository.Snapshot
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
    /// anchors, no new memory, all in one transaction. A stand-in target becomes real, with
    /// this telling as its first.
    public func mergeCandidate(_ candidate: Candidate, into target: MemoryID) throws -> MergedCandidate {
        guard candidate.kind == .memory else { throw Error.wrongKind }
        try requirePending(candidate)
        guard let out = CandidatePayload.memory(candidate) else { throw Error.badPayload }
        guard let targetMemory = try store.memories.fetch(target), let before = try store.memories.snapshot(of: target) else { throw Error.targetMissing }
        let words = try store.sessions.words(in: candidate.segmentID)
        guard !words.isEmpty, out.segmentSpan.startWord >= 0, out.segmentSpan.endWord < words.count,
              out.segmentSpan.startWord <= out.segmentSpan.endWord else { throw Error.emptySpan }

        let span = MemorySpan(memoryID: target, segmentID: candidate.segmentID,
                              startMs: words[out.segmentSpan.startWord].startMs, endMs: words[out.segmentSpan.endWord].endMs,
                              order: try store.memories.nextSpanOrder(of: target), titleText: out.title, candidateID: candidate.id)
        let edges = try edges(of: out, for: target)
        // The owner named this moment before telling it; now they have told it.
        let promotion = targetMemory.isFloating ? (title: out.title, summaryQuote: out.quote) : nil
        try store.memories.mergeSpan(span, people: edges.people, places: edges.places, anchors: edges.anchors,
                                     promotingStandIn: promotion, acceptingCandidate: candidate.id)
        let newMentions = try finishEdges(edges, segment: candidate.segmentID)
        try reindex(target)
        _ = try ResolverRunner(store: store).run()
        guard let after = try store.memories.snapshot(of: target) else { throw Error.targetMissing }
        return MergedCandidate(receipt: MergeReceipt(target: target, targetTitle: targetMemory.title, before: [before], after: after,
                                                     candidateID: candidate.id, mergedAt: .now),
                               newMentions: newMentions)
    }

    /// The card named several memories and the person said they are one (M5): every memory
    /// folds into the oldest, telling order kept, then the card joins as the last telling. One
    /// receipt, so one undo puts every memory back. Nothing changes until every name checks out.
    public func mergeGroup(_ candidate: Candidate, into memories: [MemoryID]) throws -> MergedCandidate {
        guard candidate.kind == .memory else { throw Error.wrongKind }
        try requirePending(candidate)
        guard Set(memories).count == memories.count else { throw Error.sameMemory }
        var rows: [(memory: Memory, firstTold: Date)] = []
        for id in memories {
            guard let memory = try store.memories.fetch(id) else { throw Error.targetMissing }
            rows.append((memory, try firstTelling(of: memory) ?? memory.createdAt))
        }
        // Oldest first; on a tie a real memory beats a stand-in that borrowed a span from the same session.
        rows.sort {
            if $0.firstTold != $1.firstTold { return $0.firstTold < $1.firstTold }
            if $0.memory.isFloating != $1.memory.isFloating { return !$0.memory.isFloating }
            return $0.memory.id.rawValue < $1.memory.id.rawValue
        }
        guard let oldest = rows.first?.memory else { throw Error.targetMissing }
        let later = rows.dropFirst().map(\.memory)
        guard !later.contains(where: \.isFloating) else { throw Error.standIn }
        var before: [MemoryRepository.Snapshot] = []
        for memory in [oldest] + later {
            guard let snapshot = try store.memories.snapshot(of: memory.id) else { throw Error.targetMissing }
            before.append(snapshot)
        }
        for memory in later {
            guard let target = try store.memories.fetch(oldest.id) else { throw Error.targetMissing }
            try store.memories.fold(memory, into: target)
        }
        var merged = try mergeCandidate(candidate, into: oldest.id)
        merged.receipt.before = before
        merged.receipt.targetTitle = oldest.title
        return merged
    }

    /// When a memory was first told: the session start of its order-0 span.
    private func firstTelling(of memory: Memory) throws -> Date? {
        guard let span = try store.memories.spans(of: memory.id).first,
              let segment = try store.sessions.fetchSegment(span.segmentID) else { return nil }
        return try store.sessions.fetch(segment.sessionID)?.startedAt
    }

    /// One memory becomes later tellings of another. The target keeps its title, range (unless
    /// it had none), collections and chapter (unless it had none). A stand-in target becomes
    /// real with the source's telling first; a stand-in cannot be a source.
    public func merge(_ source: MemoryID, into target: MemoryID) throws -> MergeReceipt {
        guard source != target else { throw Error.sameMemory }
        guard let targetMemory = try store.memories.fetch(target), let sourceMemory = try store.memories.fetch(source),
              let targetBefore = try store.memories.snapshot(of: target), let sourceBefore = try store.memories.snapshot(of: source) else { throw Error.targetMissing }
        guard !sourceMemory.isFloating else { throw Error.standIn }
        try store.memories.fold(sourceMemory, into: targetMemory)
        try reindex(target)
        if let chapter = try store.memories.fetch(target)?.chapterID { try chapterRangeFromMembers(chapter) }
        _ = try ResolverRunner(store: store).run()
        guard let after = try store.memories.snapshot(of: target) else { throw Error.targetMissing }
        return MergeReceipt(target: target, targetTitle: targetMemory.title, before: [targetBefore, sourceBefore], after: after, candidateID: nil, mergedAt: .now)
    }

    /// Puts both sides back. Refused when the target changed in any way since the merge (a
    /// rename, a date, a person, a hide, another telling), so a stale receipt never overwrites
    /// later work.
    public func unmerge(_ receipt: MergeReceipt) throws {
        guard let current = try store.memories.snapshot(of: receipt.target), Self.same(current, receipt.after) else { throw Error.stale }
        // One transaction: a kill mid-undo must never leave the source gone from both memories.
        try store.memories.restore(receipt.before, settingCandidate: receipt.candidateID.map { ($0, .pending) })
        for snapshot in receipt.before { try reindex(snapshot.memory.id) }
        _ = try ResolverRunner(store: store).run()
    }

    /// Equal in everything the person can change; `takenAt` and the resolver's own anchor
    /// bookkeeping (`resolved`) are not changes the person made.
    static func same(_ a: MemoryRepository.Snapshot, _ b: MemoryRepository.Snapshot) -> Bool {
        a.memory == b.memory && a.spans == b.spans && Set(a.people.map(\.personID)) == Set(b.people.map(\.personID))
            && Set(a.places.map(\.placeID)) == Set(b.places.map(\.placeID)) && Set(a.collectionIDs) == Set(b.collectionIDs)
            && a.anchors.map(\.id) == b.anchors.map(\.id)
    }
}
