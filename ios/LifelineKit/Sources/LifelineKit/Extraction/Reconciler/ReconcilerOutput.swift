import Foundation

/// One verdict on one pair. `a` and `b` echo the memory ids the request gave.
public struct PairJudgement: Codable, Sendable, Equatable {
    public var a: String
    public var b: String
    public var verdict: PairVerdict
    public var confidence: Double

    public init(a: String, b: String, verdict: PairVerdict, confidence: Double) {
        self.a = a; self.b = b; self.verdict = verdict; self.confidence = confidence
    }
}

/// The reconciler's structured output: one judgement per pair sent (M5).
public struct ReconcilerOutput: Codable, Sendable, Equatable {
    public var judgements: [PairJudgement]

    public init(judgements: [PairJudgement]) { self.judgements = judgements }
}
