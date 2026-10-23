import Foundation

public enum Stage: String, Codable, Sendable {
    case open, windDown, ended
}

public enum ArcSignal: Equatable, Sendable {
    case tick(elapsed: Duration)
    case keepGoing
    case finish
    case flags(Flags)
    case recordingLimit
    case crash
    case landed
}

public enum ArcEffect: Equatable, Sendable {
    case offerWrapUp
    case showDisclosureCard
    case land
}

public struct StageChange: Codable, Equatable, Sendable {
    public var stage: Stage
    public var at: Date
    public var reason: String
}

/// Spec §9 as revised 2026-10-22: `open → windDown → ended`. Nothing stops a session on its own
/// except the recording limit. A quick story never sees the clock. Settling in offers a wrap-up at
/// the planned length and again after the grace. A heavy moment (wants to stop, a disclosure)
/// winds the session down and is remembered for the landing. Pure: the caller supplies the clock.
public struct SessionArc: Equatable, Sendable {
    public let kind: SessionKind
    public let config: ArcConfig
    public let startedAt: Date
    public private(set) var stage: Stage = .open
    public private(set) var log: [StageChange] = []
    public private(set) var heavy = false
    public private(set) var presentDanger = false
    public private(set) var wrapUpOffered = false
    private var disclosureShown = false
    private var nextOfferAt: Duration?

    public init(kind: SessionKind, config: ArcConfig, startedAt: Date) {
        self.kind = kind; self.config = config; self.startedAt = startedAt
        log.append(StageChange(stage: .open, at: startedAt, reason: "started"))
    }

    @discardableResult
    public mutating func apply(_ signal: ArcSignal, now: Date) -> ArcEffect? {
        if stage == .ended {
            if case .landed = signal { log.append(StageChange(stage: .ended, at: now, reason: "landed")) }
            return nil
        }
        switch signal {
        case .tick(let elapsed):
            if elapsed >= config.recordingLimit { return end("recordingLimit", now) }
            guard kind == .settleIn else { return nil }
            if !wrapUpOffered, elapsed >= config.settleInPlanned {
                wrapUpOffered = true
                move(to: .windDown, "plannedLength", now)
                return .offerWrapUp
            }
            if let due = nextOfferAt, elapsed >= due {
                nextOfferAt = nil
                log.append(StageChange(stage: stage, at: now, reason: "plannedLength"))
                return .offerWrapUp
            }
            return nil
        case .keepGoing:
            log.append(StageChange(stage: stage, at: now, reason: "keepGoing"))
            nextOfferAt = .seconds(now.timeIntervalSince(startedAt)) + config.wrapUpGrace
            return nil
        case .finish:
            return end("finish", now)
        case .recordingLimit:
            return end("recordingLimit", now)
        case .crash:
            return end("crash", now)
        case .landed:
            return nil
        case .flags(let flags):
            var effect: ArcEffect?
            if flags.disclosure != .none {
                heavy = true
                if flags.disclosure == .present { presentDanger = true }
                move(to: .windDown, "disclosure", now)
                if !disclosureShown { disclosureShown = true; effect = .showDisclosureCard }
            }
            if flags.wantsToStop {
                heavy = true
                move(to: .windDown, "wantsToStop", now)
                if effect == nil { effect = .offerWrapUp }
            }
            if flags.wantsToChangeSubject {
                log.append(StageChange(stage: stage, at: now, reason: "changeSubject"))
            }
            return effect
        }
    }

    private mutating func move(to new: Stage, _ reason: String, _ now: Date) {
        stage = new
        log.append(StageChange(stage: new, at: now, reason: reason))
    }

    private mutating func end(_ reason: String, _ now: Date) -> ArcEffect {
        move(to: .ended, reason, now)
        return .land
    }

    // MARK: - stage_log

    public static func encode(_ log: [StageChange]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(log), as: UTF8.self)
    }

    public static func decode(_ json: String) throws -> [StageChange] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([StageChange].self, from: Data(json.utf8))
    }
}
