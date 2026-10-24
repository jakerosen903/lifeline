import Foundation

/// One side of a pair as the reconciler sees it: the person's words, nothing inferred.
public struct PairSide: Codable, Sendable, Equatable {
    public var memoryID: String
    public var title: String
    public var quote: String
    public var rangeText: String?

    public init(memoryID: String, title: String, quote: String, rangeText: String?) {
        self.memoryID = memoryID; self.title = title; self.quote = quote; self.rangeText = rangeText
    }

    enum CodingKeys: String, CodingKey { case memoryID = "memory_id", title, quote, rangeText = "range_text" }
}

public struct PairRequest: Codable, Sendable, Equatable {
    public var id: String
    public var a: PairSide
    public var b: PairSide

    public init(id: String, a: PairSide, b: PairSide) { self.id = id; self.a = a; self.b = b }
}

public struct ReconcileResponse: Sendable, Equatable {
    public var output: ReconcilerOutput
    public var model: String
    public var usage: Usage

    public init(output: ReconcilerOutput, model: String, usage: Usage) { self.output = output; self.model = model; self.usage = usage }
}

/// Judges pairs of memories in one batch (M5). One conformer calls the Messages API; another
/// plays a script for UI tests.
public protocol ReconcileService: Sendable {
    func judge(_ pairs: [PairRequest]) async throws(ExtractionError) -> ReconcileResponse
}

/// `ReconcileService` over the Messages API, with the reconciler's own prompt and schema.
public struct AnthropicReconcileService: ReconcileService {
    public static let promptVersion = "v1"
    private let client: AnthropicMessagesClient
    private let systemPrompt: Result<String, ExtractionError>

    public init(config: ExtractorConfig = .default, apiKey: @escaping @Sendable () -> String?, transport: any HTTPTransport = URLSessionTransport()) {
        client = AnthropicMessagesClient(config: config, apiKey: apiKey, transport: transport)
        do { systemPrompt = .success(try ExtractorPrompt.reconciler(version: Self.promptVersion)) }
        catch { systemPrompt = .failure(.missingPrompt("reconciler.\(Self.promptVersion)")) }
    }

    public func judge(_ pairs: [PairRequest]) async throws(ExtractionError) -> ReconcileResponse {
        let prompt = try systemPrompt.get()
        let user: String
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
            user = "Pairs:\n" + String(decoding: try encoder.encode(pairs), as: UTF8.self)
        } catch { throw .badRequest("pairs: \(error)") }
        let raw = try await client.extract(system: [.init(text: prompt, cached: true)], user: user, schema: ReconcilerSchema.json)
        do {
            return ReconcileResponse(output: try JSONDecoder().decode(ReconcilerOutput.self, from: raw.data), model: raw.model, usage: raw.usage)
        } catch {
            throw .badOutput("reconciler: \(error)")
        }
    }
}

/// Deterministic verdicts for UI tests: equal titles are the same moment; a "Maya" title with
/// a "blue door" title are one story; everything else is different.
public struct ScriptedReconcileService: ReconcileService {
    public init() {}

    public func judge(_ pairs: [PairRequest]) async throws(ExtractionError) -> ReconcileResponse {
        let judgements = pairs.map { pair in
            PairJudgement(a: pair.a.memoryID, b: pair.b.memoryID, verdict: Self.verdict(pair.a.title, pair.b.title), confidence: 0.9)
        }
        return ReconcileResponse(output: ReconcilerOutput(judgements: judgements), model: "scripted",
                                 usage: Usage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0))
    }

    static func verdict(_ a: String, _ b: String) -> PairVerdict {
        let x = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let y = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if x == y { return .sameMoment }
        let titles = [x, y]
        if titles.contains(where: { $0.contains("maya") }), titles.contains(where: { $0.contains("blue door") }) { return .sameStory }
        return .different
    }
}
