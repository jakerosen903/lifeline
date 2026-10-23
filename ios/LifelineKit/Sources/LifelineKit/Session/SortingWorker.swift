import Foundation

/// Sorting is durable: whatever was not sorted while the person was in the session (they
/// finished early, the network was away, the app was killed) is picked up here at the next
/// launch, session by session, newest first, with no deadline. A session being deleted is
/// skipped. A missing API key stops the whole pass after one failed request.
public actor SortingWorker {
    private let store: ExtractionStore
    private let service: any ExtractionService
    private let log: @Sendable (String) -> Void
    private var cancelled: Set<SessionID> = []
    private var active: [SessionID: ExtractionQueue] = [:]

    public static let drainDeadline: Duration = .seconds(10 * 60)

    public init(store: ExtractionStore, service: any ExtractionService, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.store = store; self.service = service; self.log = log
    }

    /// Sorts every pending segment it can. Returns how many segments were sorted.
    @discardableResult
    public func start() async -> Int {
        var sorted = 0
        let sessions = (try? store.sessions.sessionsWithPendingSegments()) ?? []
        for session in sessions where !cancelled.contains(session.id) {
            let before = pendingCount(session.id)
            guard before > 0 else { continue }
            let queue = ExtractionQueue(session: session.id, service: service, store: store, stage: "landed",
                                        drainDeadline: Self.drainDeadline, log: log)
            active[session.id] = queue
            for segment in (try? store.sessions.segments(in: session.id, status: .pending)) ?? [] {
                await queue.enqueue(segment.id)
            }
            await queue.drain()
            await queue.finish()
            active[session.id] = nil
            sorted += max(0, before - pendingCount(session.id))
            if await queue.isKeyMissing {
                log("no API key: leaving the rest pending")
                break
            }
        }
        return sorted
    }

    /// Drops this session's pending work, now and for the rest of this pass.
    public func cancel(session: SessionID) async {
        cancelled.insert(session)
        active[session] = nil
    }

    private func pendingCount(_ session: SessionID) -> Int {
        (try? store.sessions.segments(in: session, status: .pending).count) ?? 0
    }
}
