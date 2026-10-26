import Foundation

/// What a kind change took away, so Undo on the Change sheet can give it back in one write (M7).
public struct KindReceipt: Sendable, Equatable {
    public var memory: MemoryID
    public var from: MemoryKind
    public var to: MemoryKind
    /// The story place a moment gave up when it became a fact, feeling or goal.
    public var story: StoryRepository.Membership?
    /// The entities a fact, feeling or goal was about, turned into mentions when it became a moment.
    public var details: [EntityID]
}
