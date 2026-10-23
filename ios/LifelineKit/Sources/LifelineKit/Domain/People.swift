import Foundation

/// A name the owner uses for a person: "Maya", "my sister", "Mai".
public struct Alias: Codable, Sendable, Equatable {
    public var personID: PersonID
    public var text: String

    public init(personID: PersonID, text: String) {
        self.personID = personID; self.text = text
    }
}

public enum MentionStatus: String, Codable, Sendable {
    case unresolved, resolved, notAPerson = "not_a_person"
}

/// A name in a segment the app could not match: the "Who's this?" queue.
public struct Mention: Codable, Sendable, Equatable, Identifiable {
    public var id: MentionID
    public var segmentID: SegmentID
    public var text: String
    public var status: MentionStatus
    public var personID: PersonID?
    /// The kin or role phrase said with the name ("my mom"), kept so resolving adds it as an alias.
    public var relationText: String?

    public init(id: MentionID, segmentID: SegmentID, text: String, status: MentionStatus, personID: PersonID?, relationText: String? = nil) {
        self.id = id; self.segmentID = segmentID; self.text = text; self.status = status; self.personID = personID
        self.relationText = relationText
    }
}
