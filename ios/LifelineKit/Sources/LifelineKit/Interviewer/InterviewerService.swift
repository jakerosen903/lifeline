import Foundation

public enum ReplyKind: String, Codable, Sendable, CaseIterable {
    case reflection, question, none
}

/// One fast call's answer: a short spoken turn (or none) and the safety check of the newest segment.
/// Every key is required; a missing key is a bad reply.
public struct InterviewerReply: Decodable, Equatable, Sendable {
    public var kind: ReplyKind
    public var text: String?
    public var askedAboutApp: Bool
    public var disclosure: DisclosureKind
    public var wantsToStop: Bool

    public init(kind: ReplyKind, text: String?, askedAboutApp: Bool, disclosure: DisclosureKind, wantsToStop: Bool) {
        self.kind = kind; self.text = text; self.askedAboutApp = askedAboutApp
        self.disclosure = disclosure; self.wantsToStop = wantsToStop
    }

    enum CodingKeys: String, CodingKey {
        case kind, text, askedAboutApp = "asked_about_app", disclosure, wantsToStop = "wants_to_stop"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(ReplyKind.self, forKey: .kind)
        // `text` is nullable but not optional: a missing key is as wrong as any other.
        guard c.contains(.text) else { throw DecodingError.keyNotFound(CodingKeys.text, .init(codingPath: c.codingPath, debugDescription: "text")) }
        text = try c.decode(String?.self, forKey: .text)
        askedAboutApp = try c.decode(Bool.self, forKey: .askedAboutApp)
        disclosure = try c.decode(DisclosureKind.self, forKey: .disclosure)
        wantsToStop = try c.decode(Bool.self, forKey: .wantsToStop)
    }

    public var check: SafetyCheck { SafetyCheck(disclosure: disclosure, wantsToStop: wantsToStop) }

    /// Keep in step with the decoder: every property listed in `required`, `text` nullable.
    static var schema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": ReplyKind.allCases.map(\.rawValue)],
                "text": ["type": ["string", "null"]],
                "asked_about_app": ["type": "boolean"],
                "disclosure": ["type": "string", "enum": DisclosureKind.allCases.map(\.rawValue)],
                "wants_to_stop": ["type": "boolean"],
            ] as [String: Any],
            "required": ["kind", "text", "asked_about_app", "disclosure", "wants_to_stop"],
            "additionalProperties": false,
        ]
    }
}

/// What the model sees. Built by `InterviewerContext` (C2); this type only encodes it.
public struct InterviewerRequest: Equatable, Sendable {
    /// This session's closed segments, newest first.
    public var segments: [String]
    public var opening: String
    public var stage: Stage
    /// The last three turns the app spoke, oldest first.
    public var recentTurns: [String]

    public init(segments: [String], opening: String, stage: Stage, recentTurns: [String]) {
        self.segments = segments; self.opening = opening; self.stage = stage; self.recentTurns = recentTurns
    }

    private struct Body: Encodable {
        let segments: [String]
        let opening: String
        let stage: Stage
        let recentTurns: [String]
        enum CodingKeys: String, CodingKey { case segments, opening, stage, recentTurns = "recent_turns" }
    }

    /// JSON with sorted keys, so equal requests make equal messages.
    public func userMessage() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Body(segments: segments, opening: opening, stage: stage, recentTurns: recentTurns))
        return String(decoding: data, as: UTF8.self)
    }
}

public protocol InterviewerService: Sendable {
    func reply(to request: InterviewerRequest) async throws(ExtractionError) -> InterviewerReply
}
