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

    public init(settleInPlanned: Duration = .seconds(30 * 60), wrapUpGrace: Duration = .seconds(10 * 60),
                nextPromptAfterQuiet: Duration = .seconds(6), recordingLimit: Duration = .seconds(3 * 3600)) {
        self.settleInPlanned = settleInPlanned; self.wrapUpGrace = wrapUpGrace
        self.nextPromptAfterQuiet = nextPromptAfterQuiet; self.recordingLimit = recordingLimit
    }

    public static let `default` = ArcConfig()
    public static let uiTesting = ArcConfig(settleInPlanned: .seconds(8), wrapUpGrace: .seconds(4), nextPromptAfterQuiet: .seconds(2), recordingLimit: .seconds(40))
}
