import Foundation

/// One segment to extract, with everything the model is told.
public struct ExtractionRequest: Sendable, Equatable {
    public var segmentID: SegmentID
    public var segmentText: String
    public var words: [String]
    public var packet: ContextPacket

    public init(segmentID: SegmentID, segmentText: String, words: [String], packet: ContextPacket) {
        self.segmentID = segmentID; self.segmentText = segmentText; self.words = words; self.packet = packet
    }
}

public struct Usage: Sendable, Equatable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int, cacheCreationInputTokens: Int) {
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens; self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens", cacheCreationInputTokens = "cache_creation_input_tokens"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheReadInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
        cacheCreationInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
    }
}

public struct ExtractionResponse: Sendable, Equatable {
    public var output: ExtractorOutput
    public var version: String
    public var model: String
    public var usage: Usage

    public init(output: ExtractorOutput, version: String, model: String, usage: Usage) {
        self.output = output; self.version = version; self.model = model; self.usage = usage
    }
}

/// Why an extraction did not produce output. Each case maps to one behavior in the queue:
/// `noKey` stops without a request, `unauthorized` and `refused` and `truncated` and
/// `badOutput` leave the segment pending without a retry, the rest are retried.
public enum ExtractionError: Error, Equatable, Sendable {
    case noKey
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case server(status: Int)
    case network(String)
    case refused(category: String?)
    case truncated
    case badOutput(String)
    case missingPrompt(String)
    case badRequest(String)

    /// True for failures a later attempt may clear on its own.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .server, .network: true
        default: false
        }
    }
}

/// The only way the app talks to a model. One conformer calls the Messages API; another
/// plays a script for UI tests; a later server-side conformer is one new type.
public protocol ExtractionService: Sendable {
    var version: String { get }
    func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse
}
