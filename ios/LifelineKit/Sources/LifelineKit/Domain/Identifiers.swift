import Foundation

/// A typed UUID string. Each table gets its own identifier type so a `SegmentID`
/// can never be passed where a `SessionID` is expected.
public protocol TypedID: Hashable, Codable, Sendable, CustomStringConvertible {
    var rawValue: String { get }
    init(rawValue: String)
}

extension TypedID {
    public init() { self.init(rawValue: UUID().uuidString) }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public struct SessionID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct SegmentID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct PersonID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct CandidateID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MemoryID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct PlaceID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MentionID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct AnchorID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct ChapterID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct CollectionID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct StoryID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct DuplicatePairID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct CuriosityItemID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct EntityID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
