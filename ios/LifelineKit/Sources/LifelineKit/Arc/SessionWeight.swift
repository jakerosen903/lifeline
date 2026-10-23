import Foundation

/// Whether a session had a heavy moment, read back from what was stored: the flag rows the
/// extractor wrote and the stage log. The live arc knows this too, but a flag can arrive after
/// Finish and a crash forgets the arc; the landing must get it right from storage alone.
public struct SessionWeight: Equatable, Sendable {
    public var heavy: Bool
    public var presentDanger: Bool

    public init(heavy: Bool, presentDanger: Bool) { self.heavy = heavy; self.presentDanger = presentDanger }

    public static func of(candidates: [Candidate]) -> SessionWeight {
        var weight = SessionWeight(heavy: false, presentDanger: false)
        for candidate in candidates where candidate.kind == .flag {
            guard let flags = try? CandidatePayload.decode(Flags.self, from: candidate.payload) else { continue }
            if flags.isHeavy { weight.heavy = true }
            if flags.disclosure == .present { weight.presentDanger = true }
        }
        return weight
    }

    public static func of(log: [StageChange]) -> SessionWeight {
        SessionWeight(heavy: log.contains { $0.reason.hasPrefix("disclosure") || $0.reason == "wantsToStop" },
                      presentDanger: log.contains { $0.reason == "disclosure:present" })
    }

    public static func || (a: SessionWeight, b: SessionWeight) -> SessionWeight {
        SessionWeight(heavy: a.heavy || b.heavy, presentDanger: a.presentDanger || b.presentDanger)
    }
}
