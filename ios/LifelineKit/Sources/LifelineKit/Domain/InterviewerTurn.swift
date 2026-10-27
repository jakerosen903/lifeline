import Foundation

/// What a spoken interviewer turn is for (M8).
public enum TurnKind: String, Codable, CaseIterable, Sendable {
    case opening, reflection, question, wrapUp, earlyWindDown, disclosure, aboutApp

    /// Turns that ask the person something. Rule 7 counts these.
    public var isQuestion: Bool { self == .opening || self == .question }
}

/// Where a turn's words came from: the app's own copy, or the interviewer model.
public enum TurnSource: String, Codable, Sendable {
    case fixed, model
}

/// One thing the interviewer said, on the session file's clock. `endMs` is nil until the turn stops;
/// `interrupted` is true when the person spoke over it.
public struct InterviewerTurn: Codable, Sendable, Equatable, Identifiable {
    public var id: InterviewerTurnID
    public var sessionID: SessionID
    public var kind: TurnKind
    public var source: TurnSource
    public var text: String
    public var startMs: Milliseconds
    public var endMs: Milliseconds?
    public var interrupted: Bool

    public init(id: InterviewerTurnID, sessionID: SessionID, kind: TurnKind, source: TurnSource, text: String,
                startMs: Milliseconds, endMs: Milliseconds?, interrupted: Bool) {
        self.id = id; self.sessionID = sessionID; self.kind = kind; self.source = source; self.text = text
        self.startMs = startMs; self.endMs = endMs; self.interrupted = interrupted
    }
}
