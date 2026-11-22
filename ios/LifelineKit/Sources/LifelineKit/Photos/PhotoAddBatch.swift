/// The picks in flight on one page: how many photos were picked, how many are done, how many failed. A pick is
/// `begin(count:)`, then `finishOne()` per photo (after `fail(_:)` for a photo that could not be added), then `end()`.
/// The owner can open the picker again while photos are added: the second pick joins the count, and the failure
/// line comes once, when the last pick ends.
public struct PhotoAddBatch: Sendable, Equatable {
    public private(set) var picked = 0
    public private(set) var done = 0
    public private(set) var failed = 0
    private var lastError = ""
    private var picks = 0

    public init() {}

    public var isActive: Bool { picks > 0 }

    /// "Adding photo {i} of {n}…" while a pick is open; nil otherwise. It never runs past the last photo.
    public var line: String? {
        guard isActive, picked > 0 else { return nil }
        return PhotoAddProgress.line(adding: min(done + 1, picked), of: picked)
    }

    public mutating func begin(count: Int) {
        picks += 1
        picked += max(0, count)
    }

    public mutating func finishOne() { done += 1 }

    /// `error` is the reason in the owner's words; the last one is kept for a pick with one failure.
    public mutating func fail(_ error: String) {
        failed += 1
        lastError = error
    }

    /// Closes one pick. When it was the last open pick, returns the failure line, if any, and starts clean.
    /// An unmatched `end()` is a caller's bug; it changes nothing.
    public mutating func end() -> String? {
        guard isActive else { return nil }
        picks -= 1
        guard picks == 0 else { return nil }
        let line = PhotoAddProgress.failureLine(failed: failed, lastError: lastError)
        self = PhotoAddBatch()
        return line
    }
}
