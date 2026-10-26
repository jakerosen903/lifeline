import Foundation

/// Two ways in, different in shape rather than in length: a quick story answers one prompt and
/// ends when the person is done; settling in is a conversation that offers the next question and,
/// at the planned length, a wrap-up.
public enum SessionKind: String, Codable, Sendable, CaseIterable {
    case quick, settleIn
}

/// The arc's numbers. Configuration, not code. A quick story has no time element at all.
public struct ArcConfig: Sendable, Equatable {
    /// When settling in offers the wrap-up.
    public var settleInPlanned: Duration
    /// After "Keep going", how long before the wrap-up is offered again.
    public var wrapUpGrace: Duration
    /// Quiet after a closed segment before settling in offers the next question.
    public var nextPromptAfterQuiet: Duration
    /// The one automatic landing: a real file limit.
    public var recordingLimit: Duration
    /// Quiet after the person pauses before the interviewer asks for a reflection (PRINCIPLES: 1 to 2 s).
    public var replyGrace: Duration
    /// How long a transcriber partial keeps the floor for the person, even after a pause.
    public var partialHoldsFloor: Duration

    public init(settleInPlanned: Duration = .seconds(30 * 60), wrapUpGrace: Duration = .seconds(10 * 60),
                nextPromptAfterQuiet: Duration = .seconds(6), recordingLimit: Duration = .seconds(3 * 3600),
                replyGrace: Duration = .seconds(1.5), partialHoldsFloor: Duration = .seconds(1)) {
        self.settleInPlanned = settleInPlanned; self.wrapUpGrace = wrapUpGrace
        self.nextPromptAfterQuiet = nextPromptAfterQuiet; self.recordingLimit = recordingLimit
        self.replyGrace = replyGrace; self.partialHoldsFloor = partialHoldsFloor
    }

    public static let `default` = ArcConfig()
    public static let uiTesting = ArcConfig(settleInPlanned: .seconds(8), wrapUpGrace: .seconds(4), nextPromptAfterQuiet: .seconds(2), recordingLimit: .seconds(40),
                                            replyGrace: .seconds(0.3), partialHoldsFloor: .seconds(1))
}
