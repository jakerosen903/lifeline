import Foundation

/// What Undo takes back after kept cards close: the cards as they were and every suggestion
/// their closes dismissed. Closes inside one undo window add up, so a second close never drops
/// the first close's Undo.
public struct KeptCloseUndo: Equatable, Sendable {
    public private(set) var cards: [KeptCard] = []
    public private(set) var dismissed: [Candidate] = []

    public init() {}

    public var isEmpty: Bool { dismissed.isEmpty }

    /// One more close. A close that dismissed nothing adds nothing: there is nothing to take back.
    public mutating func add(cards closed: [KeptCard], dismissed more: [Candidate]) {
        guard !more.isEmpty else { return }
        cards += closed.filter { card in !cards.contains { $0.memoryCandidateID == card.memoryCandidateID } }
        dismissed += more.filter { candidate in !dismissed.contains { $0.id == candidate.id } }
    }

    /// The notice text, or nil when there is nothing to undo.
    public var notice: String? {
        switch dismissed.count {
        case 0: nil
        case 1: "1 suggestion dismissed."
        default: "\(dismissed.count) suggestions dismissed."
        }
    }
}
