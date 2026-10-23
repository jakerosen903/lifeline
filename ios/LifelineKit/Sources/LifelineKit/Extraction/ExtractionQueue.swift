import Foundation

public enum ExtractionEvent: Sendable, Equatable {
    /// Accepted candidates for a segment, in ordinal order. Rejected ones are stored, not sent.
    case candidates([Candidate], segment: SegmentID)
    case flags(Flags, segment: SegmentID)
    case failed(segment: SegmentID, ExtractionError)
    case skipped(segment: SegmentID)
}

/// Per-session extraction. Segments are processed one at a time in arrival order, so
/// candidates and their ordinals are stable. A failure leaves the segment pending and moves
/// on; `drain()` retries pending segments once, which is what Stop calls. A missing key stops
/// requests for the rest of the session: the person is told once, not once per segment.
public actor ExtractionQueue {
    public nonisolated let events: AsyncStream<ExtractionEvent>
    private let emit: AsyncStream<ExtractionEvent>.Continuation

    private let session: SessionID
    private let service: any ExtractionService
    private let store: ExtractionStore
    private let stage: String
    private let log: @Sendable (String) -> Void

    private var waiting: [SegmentID] = []
    private var running = false
    private var keyMissing = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(session: SessionID, service: any ExtractionService, store: ExtractionStore, stage: String = "open",
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.session = session; self.service = service; self.store = store; self.stage = stage; self.log = log
        (events, emit) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public func enqueue(_ segment: SegmentID) {
        waiting.append(segment)
        startWorkerIfNeeded()
    }

    /// Waits for the queue to empty, retries every still-pending segment once, waits again.
    public func drain() async {
        await waitUntilIdle()
        guard !keyMissing else { return }
        let pending = (try? store.sessions.segments(in: session, status: .pending)) ?? []
        guard !pending.isEmpty else { return }
        log("retrying \(pending.count) pending segment(s)")
        for segment in pending { waiting.append(segment.id) }
        startWorkerIfNeeded()
        await waitUntilIdle()
    }

    public func finish() {
        emit.finish()
    }

    // MARK: - Worker

    private func startWorkerIfNeeded() {
        guard !running else { return }
        running = true
        Task { await self.work() }
    }

    private func work() async {
        while !waiting.isEmpty {
            let segment = waiting.removeFirst()
            await process(segment)
        }
        running = false
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func waitUntilIdle() async {
        guard running || !waiting.isEmpty else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func process(_ segmentID: SegmentID) async {
        if keyMissing {
            emit.yield(.failed(segment: segmentID, .noKey))
            return
        }
        do {
            guard let segment = try store.sessions.fetchSegment(segmentID) else { return }
            if try store.candidates.hasCandidates(for: segmentID, version: service.version) {
                emit.yield(.skipped(segment: segmentID))
                return
            }
            let words = try store.sessions.words(in: segmentID).map(\.text)
            let request = ExtractionRequest(segmentID: segmentID, segmentText: segment.text, words: words, packet: try packet(for: segment))
            let response = try await service.extract(request)
            let validated = OutputValidator.validate(response.output, segmentText: segment.text, words: words)
            let accepted = try storeCandidates(validated, segment: segmentID, version: response.version)
            try store.sessions.setStatus(.extracted, for: segmentID)
            log("segment \(segment.index): \(accepted.count) shown, \(validated.rejected.count) rejected, "
                + "\(response.usage.inputTokens) in / \(response.usage.outputTokens) out, cache read \(response.usage.cacheReadInputTokens)")
            emit.yield(.candidates(accepted, segment: segmentID))
            if validated.flags.isAnySet { emit.yield(.flags(validated.flags, segment: segmentID)) }
        } catch let error as ExtractionError {
            if error == .noKey { keyMissing = true }
            log("segment \(segmentID) failed: \(error)")
            emit.yield(.failed(segment: segmentID, error))
        } catch {
            log("segment \(segmentID) store error: \(error)")
            emit.yield(.failed(segment: segmentID, .badOutput("store: \(error)")))
        }
    }

    private func packet(for segment: Segment) throws -> ContextPacket {
        let previous = try store.sessions.segments(in: session)
        let people = try store.people.people().map { ($0, (try? store.people.aliases(of: $0.id)) ?? []) }
        let memories = try store.memories.memories(in: session)
        let freeText = try store.profile.fetch()?.freeText
        return ContextPacketBuilder.build(segment: segment, previous: previous, people: people, memories: memories,
                                          profileFreeText: freeText, stage: stage)
    }

    /// Writes one row per candidate in output order; rejected rows are dismissed with the reason.
    /// A flag row follows when any flag is set. Returns the rows to show.
    private func storeCandidates(_ validated: OutputValidator.Validated, segment: SegmentID, version: String) throws -> [Candidate] {
        var ordinal = 0
        var shown: [Candidate] = []
        func row(_ kind: CandidateKind, _ payload: String, _ confidence: Double, _ rejection: String?) -> Candidate {
            defer { ordinal += 1 }
            return Candidate(id: .init(), segmentID: segment, extractorVersion: version, ordinal: ordinal, kind: kind, payload: payload,
                             confidence: confidence, status: rejection == nil ? .pending : .dismissed, rejection: rejection, createdAt: .now)
        }
        for candidate in validated.accepted {
            let r = try Self.describe(candidate)
            let c = row(r.kind, r.payload, r.confidence, nil)
            try store.candidates.insert(c)
            shown.append(c)
        }
        for rejected in validated.rejected {
            let r = try Self.describe(rejected.candidate)
            try store.candidates.insert(row(r.kind, r.payload, r.confidence, rejected.reason))
        }
        if validated.flags.isAnySet {
            try store.candidates.insert(row(.flag, try CandidatePayload.encode(validated.flags), 1, nil))
        }
        return shown
    }

    private static func describe(_ candidate: OutputValidator.ValidatedCandidate) throws -> (kind: CandidateKind, payload: String, confidence: Double) {
        switch candidate {
        case .memory(let m): return (.memory, try CandidatePayload.encode(m), m.confidence)
        case .mention(let m): return (m.kind == .person ? .person : .place, try CandidatePayload.encode(m), m.confidence)
        }
    }
}
