import Foundation

/// "Are these the same?": Same story merges the newer memory into the older; Keep separate
/// remembers the answer so the pair never returns; undo puts both back (M5).
extension CandidateActions {
    /// Refused as stale when the pair was already answered or either memory is gone, so a
    /// card left on screen across a merge or delete never acts on the wrong rows. The pair row
    /// goes with the folded memory (cascade): one side no longer exists, so it cannot be found again.
    public func samePair(_ pair: DuplicatePair) throws -> MergeReceipt {
        let (a, b) = try openSides(of: pair)
        let (older, newer) = PairFinder.ordered(a, b)
        return try merge(newer.id, into: older.id)
    }

    public func separatePair(_ pair: DuplicatePair) throws {
        _ = try openSides(of: pair)
        try store.pairs.setStatus(pair.id, .separate)
    }

    /// Undo of Same story on a pair: the merge comes apart and the pair is open again, its
    /// row written back since the merge took it with the folded memory.
    public func undoPair(_ receipt: MergeReceipt, pair: DuplicatePair) throws {
        try unmerge(receipt)
        var reopened = pair
        reopened.status = .open
        reopened.decidedAt = nil
        if try store.pairs.pair(id: pair.id) == nil { try store.pairs.insert(reopened) } else { try store.pairs.setStatus(pair.id, .open) }
    }

    private func openSides(of pair: DuplicatePair) throws -> (Memory, Memory) {
        guard let current = try store.pairs.pair(id: pair.id), current.status == .open,
              let a = try store.memories.fetch(current.aMemoryID), let b = try store.memories.fetch(current.bMemoryID) else { throw Error.stale }
        return (a, b)
    }
}
