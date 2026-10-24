import Foundation
import Synchronization

/// What the sorting machinery says about itself, for the status line (M6). The worker and
/// every live queue count as activity; the last failure is kept until a segment succeeds;
/// the duplicate pass says when it is running. One instance per app, owned by the composition root.
public final class SortingReporter: Sendable {
    public struct Snapshot: Sendable, Equatable {
        public var active: Bool
        public var lastFailure: ExtractionError?
        public var checkingRepeats: Bool
    }

    private struct State { var activeCount = 0; var lastFailure: ExtractionError?; var checkingRepeats = false; var onChange: @Sendable () -> Void = {} }
    private let state = Mutex(State())

    public init() {}

    /// Called after every change, off any particular actor.
    public var onChange: @Sendable () -> Void {
        get { state.withLock { $0.onChange } }
        set { state.withLock { $0.onChange = newValue } }
    }

    /// Nested: two things sorting at once stay active until both stop.
    public func activityChanged(active: Bool) {
        change { $0.activeCount = max(0, $0.activeCount + (active ? 1 : -1)) }
    }

    public func failed(_ error: ExtractionError) { change { $0.lastFailure = error } }

    /// A segment sorted: whatever failed before is behind us.
    public func cleared() { change { $0.lastFailure = nil } }

    public func passChanged(running: Bool) { change { $0.checkingRepeats = running } }

    public func snapshot() -> Snapshot {
        state.withLock { Snapshot(active: $0.activeCount > 0, lastFailure: $0.lastFailure, checkingRepeats: $0.checkingRepeats) }
    }

    private func change(_ body: (inout State) -> Void) {
        let handler = state.withLock { s in body(&s); return s.onChange }
        handler()
    }
}
