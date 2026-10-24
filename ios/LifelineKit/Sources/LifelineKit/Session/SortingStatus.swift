import Foundation

/// What is still being sorted, as one line the person can read (M6). Pure apart from `current`.
public struct SortingStatus: Sendable, Equatable {
    public struct Pending: Sendable, Equatable {
        public var session: Session
        public var count: Int
        public init(session: Session, count: Int) { self.session = session; self.count = count }
    }

    public var pending: [Pending]
    public var active: Bool
    public var lastFailure: ExtractionError?
    public var checkingRepeats: Bool
    public var hasKey: Bool

    public init(pending: [Pending], active: Bool, lastFailure: ExtractionError?, checkingRepeats: Bool, hasKey: Bool) {
        self.pending = pending; self.active = active; self.lastFailure = lastFailure; self.checkingRepeats = checkingRepeats; self.hasKey = hasKey
    }

    public static let empty = SortingStatus(pending: [], active: false, lastFailure: nil, checkingRepeats: false, hasKey: true)

    public var isEmpty: Bool { pending.isEmpty && !checkingRepeats }
    public var pendingCount: Int { pending.reduce(0) { $0 + $1.count } }
    /// The key line: there is work and no key to do it with.
    public var needsKey: Bool { !pending.isEmpty && (!hasKey || lastFailure == .noKey) }
    /// "Try again": work is waiting and nothing is doing it.
    public var canRetry: Bool { !pending.isEmpty && !active && !needsKey }

    /// Pending counts from the store (hidden recordings included; deleted ones are gone), activity from the reporter.
    public static func current(store: ExtractionStore, reporter: SortingReporter, hasKey: Bool) throws -> SortingStatus {
        let pending = try store.sessions.sessionsWithPendingSegments().map {
            Pending(session: $0, count: try store.sessions.segments(in: $0.id, status: .pending).count)
        }.filter { $0.count > 0 }
        let s = reporter.snapshot()
        return SortingStatus(pending: pending, active: s.active, lastFailure: s.lastFailure, checkingRepeats: s.checkingRepeats, hasKey: hasKey)
    }

    /// Precedence: the key line, then "Not sorting right now", then "Still sorting…", then "Checking for repeats…".
    public func line(now: Date = .now, calendar: Calendar = .current) -> String? {
        if needsKey { return "Add a key in Settings to sort what you say" }
        if !pending.isEmpty && !active { return "Not sorting right now" }
        if !pending.isEmpty {
            let n = pendingCount
            let moments = n == 1 ? "1 moment" : "\(n) moments"
            let from: String
            if pending.count > 1 {
                from = "\(pending.count) recordings"
            } else {
                from = Self.whichRecording(pending[0].session.startedAt, now: now, calendar: calendar)
            }
            return "Still sorting \(moments) from \(from)…"
        }
        if checkingRepeats { return "Checking for repeats…" }
        return nil
    }

    /// "today's recording", "Thursday's recording" within the week, "Sep 24's recording" beyond.
    static func whichRecording(_ started: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(started, inSameDayAs: now) { return "today's recording" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: started), to: calendar.startOfDay(for: now)).day ?? 0
        var formatter = Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)
        if days < 7 {
            formatter = formatter.weekday(.wide)
            let weekday = started.formatted(formatter.weekday(.wide).month(.omitted).day(.omitted).year(.omitted))
            return "\(weekday)'s recording"
        }
        let day = started.formatted(formatter.month(.abbreviated).day().year(.omitted))
        return "\(day)'s recording"
    }
}
