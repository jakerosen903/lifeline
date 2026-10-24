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
        // The card's edges and its continuations', as one telling (M5).
        let continuations = try store.candidates.continuations(of: candidate.id)
        var edges = try edges(of: out, for: target)
        for row in continuations.compactMap(CandidatePayload.memory) { edges.merge(try self.edges(of: row, for: target)) }
        // The owner named this moment before telling it; now they have told it.
        let promotion = targetMemory.isFloating ? (title: out.title, summaryQuote: out.quote) : nil
        try store.memories.mergeSpan(span, continuations: try continuationSpans(of: out, for: target), people: edges.people, places: edges.places,
                                     anchors: edges.anchors, promotingStandIn: promotion, acceptingCandidate: candidate.id,
                                     acceptingContinuations: continuations.map(\.id))
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
        // The card is checked before anything folds, so a refused card leaves every memory alone.
        guard let out = CandidatePayload.memory(candidate) else { throw Error.badPayload }
        let words = try store.sessions.words(in: candidate.segmentID)
        guard !words.isEmpty, out.segmentSpan.startWord >= 0, out.segmentSpan.endWord < words.count,
              out.segmentSpan.startWord <= out.segmentSpan.endWord else { throw Error.emptySpan }
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
        // Folds and the card's span in one transaction; the card's edges and its continuations' as one telling.
        let span = MemorySpan(memoryID: oldest.id, segmentID: candidate.segmentID,
                              startMs: words[out.segmentSpan.startWord].startMs, endMs: words[out.segmentSpan.endWord].endMs,
                              order: 0, titleText: out.title, candidateID: candidate.id)
        let continuations = try store.candidates.continuations(of: candidate.id)
        var edges = try edges(of: out, for: oldest.id)
        for row in continuations.compactMap(CandidatePayload.memory) { edges.merge(try self.edges(of: row, for: oldest.id)) }
        let promotion = oldest.isFloating && later.isEmpty ? (title: out.title, summaryQuote: out.quote) : nil
        try store.memories.mergeGroup(sources: later, into: oldest, span: span, continuations: try continuationSpans(of: out, for: oldest.id),
                                      people: edges.people, places: edges.places, anchors: edges.anchors,
                                      promotingStandIn: promotion, acceptingCandidate: candidate.id, acceptingContinuations: continuations.map(\.id))
        let newMentions = try finishEdges(edges, segment: candidate.segmentID)
        try reindex(oldest.id)
        if let chapter = try store.memories.fetch(oldest.id)?.chapterID { try chapterRangeFromMembers(chapter) }
        _ = try ResolverRunner(store: store).run()
        guard let after = try store.memories.snapshot(of: oldest.id) else { throw Error.targetMissing }
        return MergedCandidate(receipt: MergeReceipt(target: oldest.id, targetTitle: oldest.title, before: before, after: after,
                                                     candidateID: candidate.id, mergedAt: .now),
                               newMentions: newMentions)
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

    /// "Separate this telling" (M5): a later telling becomes its own memory again, with the
    /// spans that carried it on, the anchors, people and place only its card named, and the
    /// card as its origin. The original re-derives its date unless the person stated one.
    public func separateTelling(_ memory: MemoryID, order: Int) throws -> Memory {
        guard order != 0 else { throw Error.wrongKind }
        guard let original = try store.memories.fetch(memory) else { throw Error.targetMissing }
        let spans = try store.memories.spans(of: memory)
        guard let span = spans.first(where: { $0.order == order }) else { throw Error.targetMissing }
        let card = try span.candidateID.flatMap { try store.candidates.fetch($0) }
        let out = card.flatMap(CandidatePayload.memory)
        let segmentText = try store.sessions.fetchSegment(span.segmentID)?.text ?? ""
        let fresh = Memory(id: .init(), title: span.titleText ?? original.title, summaryQuote: out?.quote ?? segmentText, visibility: original.visibility,
                           chapterID: nil, createdFromCandidateID: span.candidateID, createdAt: .now, hiddenFromTimeline: original.hiddenFromTimeline)

        // What this telling alone named goes with it; what another telling also named stays.
        let leaving = try tellingOutputs(of: span, card: card)
        let staying = try spans.filter { $0.order != order && $0.continuesOrder != order }
            .flatMap { try tellingOutputs(of: $0, card: try $0.candidateID.flatMap { try store.candidates.fetch($0) }) }
            + (original.createdFromCandidateID.flatMap { try? store.candidates.fetch($0) }.flatMap(CandidatePayload.memory).map { [$0] } ?? [])
        let leavingAnchors = leaving.flatMap(\.anchors), stayingAnchors = staying.flatMap(\.anchors)
        let anchors = try store.memories.anchors(of: memory).filter { anchor in
            leavingAnchors.contains(where: { $0.phrase == anchor.phrase && $0.relation == anchor.relation })
                && !stayingAnchors.contains(where: { $0.phrase == anchor.phrase && $0.relation == anchor.relation })
        }.map(\.id)
        let leavingPeople = try people(named: leaving.flatMap(\.peopleRefs)), stayingPeople = try people(named: staying.flatMap(\.peopleRefs))
        let leavingPlaces = Set(leaving.compactMap(\.placeText).map { $0.lowercased() }), stayingPlaces = Set(staying.compactMap(\.placeText).map { $0.lowercased() })
        let places = try store.memories.places(of: memory)
            .filter { leavingPlaces.contains($0.nameText.lowercased()) && !stayingPlaces.contains($0.nameText.lowercased()) }.map(\.id)
        // A date the anchors gave (the resolver stamps "in 1998" as stated, phrase as evidence) goes
        // with the telling that said it; a date the person typed on "Tell me when" stays.
        let fromLeavingAnchor = leavingAnchors.contains { $0.phrase.caseInsensitiveCompare(original.range.evidenceText ?? "") == .orderedSame }
        // The spans, the edges and the range in one transaction.
        try store.memories.separate(memory, order: order, into: fresh,
                                    moving: .init(anchors: anchors, people: Array(leavingPeople.subtracting(stayingPeople)), places: places),
                                    clearRange: !original.range.isSettled || fromLeavingAnchor)
        try reindex(memory)
        try reindex(fresh.id)
        _ = try ResolverRunner(store: store).run()
        return try store.memories.fetch(fresh.id) ?? fresh
    }

    /// The payloads behind one telling: its card and the card's continuations.
    private func tellingOutputs(of span: MemorySpan, card: Candidate?) throws -> [MemoryOut] {
        guard let card, let out = CandidatePayload.memory(card) else { return [] }
        return [out] + (try store.candidates.continuations(of: card.id)).compactMap(CandidatePayload.memory)
    }

    private func people(named refs: [String]) throws -> Set<PersonID> {
        Set(try refs.compactMap { try store.people.findPerson(matching: $0)?.id })
    }

    /// Puts both sides back. Refused when the target changed in any way since the merge (a
    /// rename, a date, a person, a hide, another telling), so a stale receipt never overwrites
    /// later work.
    public func unmerge(_ receipt: MergeReceipt) throws {
        try unmerge(receipt, reopeningPair: nil)
    }

    /// `reopeningPair` is written back open in the same transaction (undo of Same story on a pair).
    func unmerge(_ receipt: MergeReceipt, reopeningPair pair: DuplicatePair?) throws {
        guard let current = try store.memories.snapshot(of: receipt.target), Self.same(current, receipt.after) else { throw Error.stale }
        // One transaction: a kill mid-undo must never leave the source gone from both memories,
        // or the memories back with the pair's answer lost.
        try store.memories.restore(receipt.before, settingCandidate: receipt.candidateID.map { ($0, .pending) }, reopeningPair: pair)
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
