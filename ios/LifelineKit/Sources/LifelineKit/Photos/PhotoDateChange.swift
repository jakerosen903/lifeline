import Foundation

/// What "Undo" needs for one memory: the range before the tap, and the day the tap wrote.
public struct PhotoDateChange: Sendable, Equatable {
    public var memory: MemoryID
    public var before: TimeRange
    public var date: CivilDate

    public init(memory: MemoryID, before: TimeRange, date: CivilDate) {
        self.memory = memory; self.before = before; self.date = date
    }
}
