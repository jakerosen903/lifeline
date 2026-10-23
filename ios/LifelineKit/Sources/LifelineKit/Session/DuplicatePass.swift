import Foundation

/// Finds memories that may be the same moment and asks the reconciler, in one batch, after
/// the embedding backfill at launch and a little after every Keep. Its verdicts become
/// `duplicate_pair` rows: the person decides on a card; the pass never merges (M5).
public actor DuplicatePass {
    private let store: ExtractionStore
    private let matcher: MemoryMatcher
    private let reconcile: any ReconcileService
    private let actions: CandidateActions
    private let config: PairConfig
    private let log: @Sendable (String) -> Void
    private var scheduled: Task<Void, Never>?
    private var running = false

    public static let debounce: Duration = .seconds(2)

    public init(store: ExtractionStore, matcher: MemoryMatcher, reconcile: any ReconcileService, actions: CandidateActions,
                config: PairConfig = .default, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.store = store; self.matcher = matcher; self.reconcile = reconcile; self.actions = actions; self.config = config; self.log = log
    }

    /// One pass: up to `pairBatch` new pairs judged and written. Returns how many were judged.
    /// A missing key ends the pass quietly; any other failure is logged and leaves nothing behind.
    @discardableResult
    public func run() async -> Int {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let found: [PairFinder.Candidate]
        do { found = Array(try PairFinder(store: store, matcher: matcher, config: config).candidates().prefix(config.pairBatch)) }
        catch { log("[duplicates] store error: \(error)"); return 0 }
        guard !found.isEmpty else { return 0 }
        let requests = found.map { pair in
            PairRequest(id: PairKey(pair.a.id, pair.b.id).low.rawValue + "|" + PairKey(pair.a.id, pair.b.id).high.rawValue,
                        a: Self.side(pair.a), b: Self.side(pair.b))
        }
        let response: ReconcileResponse
        do { response = try await reconcile.judge(requests) }
        catch ExtractionError.noKey { return 0 }
        catch { log("[duplicates] reconciler failed: \(error)"); return 0 }
        var written = 0
        for pair in found {
            guard let judgement = response.output.judgements.first(where: { Set([$0.a, $0.b]) == Set([pair.a.id.rawValue, pair.b.id.rawValue]) }) else { continue }
            let status: PairStatus = judgement.verdict == .different ? .separate : .open
            let row = DuplicatePair(id: .init(), aMemoryID: pair.a.id, bMemoryID: pair.b.id, score: pair.score, verdict: judgement.verdict,
                                    status: status, decidedAt: status == .open ? nil : .now)
            do { try store.pairs.insert(row); written += 1 } catch { log("[duplicates] could not write a pair: \(error)") }
        }
        let open = response.output.judgements.filter { $0.verdict != .different }.count
        log("[duplicates] \(written) pair(s) judged by \(response.model), \(open) to ask, \(response.usage.inputTokens) in / \(response.usage.outputTokens) out")
        return written
    }

    /// Runs once, a couple of seconds after the last request, so a run of Keeps costs one call.
    public func requestRun() {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    private static func side(_ memory: Memory) -> PairSide {
        PairSide(memoryID: memory.id.rawValue, title: memory.title, quote: memory.summaryQuote,
                 rangeText: memory.range.isPlaced ? memory.range.displayText : nil)
    }
}
