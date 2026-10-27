import Foundation

/// Raw HTTP to the Messages API: builds the one request shape the spec fixes, retries what is
/// transient, and reads `stop_reason` before touching `content`. No module outside Extraction
/// imports this.
public struct AnthropicMessagesClient: Sendable {
    public struct SystemBlock: Sendable, Equatable {
        public var text: String
        /// True puts the cache breakpoint on this block. Only the fixed prompt is cached.
        public var cached: Bool
        public init(text: String, cached: Bool) { self.text = text; self.cached = cached }
    }

    public struct Reply: Sendable, Equatable {
        public var output: ExtractorOutput
        public var model: String
        public var usage: Usage
    }

    /// The model's text, undecoded, for callers with their own schema (the reconciler, M5).
    public struct RawReply: Sendable, Equatable {
        public var data: Data
        public var model: String
        public var usage: Usage
    }

    /// A server-named wait longer than this is not worth holding a session for.
    public static let maxRetryDelay: Duration = .seconds(10)

    private let config: ExtractorConfig
    private let apiKey: @Sendable () -> String?
    private let transport: any HTTPTransport
    private let sleep: @Sendable (Duration) async -> Void

    public init(config: ExtractorConfig, apiKey: @escaping @Sendable () -> String?, transport: any HTTPTransport,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.config = config; self.apiKey = apiKey; self.transport = transport; self.sleep = sleep
    }

    /// The extractor's call: its schema, its output type.
    public func extract(system: [SystemBlock], user: String) async throws(ExtractionError) -> Reply {
        let raw = try await extract(system: system, user: user, schema: ExtractorSchema.json)
        do {
            return Reply(output: try ExtractorOutput.decode(from: raw.data), model: raw.model, usage: raw.usage)
        } catch {
            throw .badOutput("output: \(error)")
        }
    }

    /// One structured call with any schema. Same request shape, retries and stop-reason checks.
    public func extract(system: [SystemBlock], user: String, schema: [String: Any]) async throws(ExtractionError) -> RawReply {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { throw .noKey }
        let request: URLRequest
        do { request = try makeRequest(key: key, system: system, user: user, schema: schema) } catch { throw .badRequest("\(error)") }

        var lastError: ExtractionError = .network("no attempt")
        let attempts = max(1, config.maxAttempts)
        for attempt in 1...attempts {
            do {
                let (data, response) = try await transport.send(request)
                switch response.statusCode {
                case 200: return try parse(data)
                case 401, 403: throw ExtractionError.unauthorized
                case 400, 404, 413: throw ExtractionError.badRequest(Self.errorMessage(data) ?? "\(response.statusCode)")
                case 429: lastError = .rateLimited(retryAfterSeconds: Self.retryAfter(response))
                default: lastError = .server(status: response.statusCode)
                }
            } catch let error as ExtractionError {
                throw error
            } catch {
                lastError = .network(error.localizedDescription)
            }
            if attempt < attempts { await sleep(Self.delay(for: lastError, attempt: attempt)) }
        }
        throw lastError
    }

    // MARK: - Request

    private func makeRequest(key: String, system: [SystemBlock], user: String, schema: [String: Any]) throws -> URLRequest {
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "system": system.map { block -> [String: Any] in
                var b: [String: Any] = ["type": "text", "text": block.text]
                if block.cached { b["cache_control"] = ["type": "ephemeral"] }
                return b
            },
            "messages": [["role": "user", "content": user]],
            "output_config": ["effort": config.effort, "format": ["type": "json_schema", "schema": schema]],
        ]
        if config.thinkingDisabled { body["thinking"] = ["type": "disabled"] }
        if config.betas.contains(where: { $0.hasPrefix("server-side-fallback") }) { body["fallbacks"] = "default" }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(config.apiVersion, forHTTPHeaderField: "anthropic-version")
        if !config.betas.isEmpty { request.setValue(config.betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: - Response

    private struct MessageResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        struct StopDetails: Decodable { let category: String? }
        let model: String
        let stopReason: String?
        let stopDetails: StopDetails?
        let content: [Block]
        let usage: Usage
        enum CodingKeys: String, CodingKey { case model, stopReason = "stop_reason", stopDetails = "stop_details", content, usage }
    }

    private func parse(_ data: Data) throws(ExtractionError) -> RawReply {
        let message: MessageResponse
        do { message = try JSONDecoder().decode(MessageResponse.self, from: data) } catch { throw .badOutput("response: \(error)") }
        switch message.stopReason {
        case "refusal": throw .refused(category: message.stopDetails?.category)
        case "max_tokens": throw .truncated
        default: break
        }
        let text = message.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        return RawReply(data: Data(text.utf8), model: message.model, usage: message.usage)
    }

    private static func errorMessage(_ data: Data) -> String? {
        struct ErrorBody: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: "retry-after").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// 1 s, 2 s, 4 s, unless the server named a wait (capped at `maxRetryDelay`).
    static func delay(for error: ExtractionError, attempt: Int) -> Duration {
        if case .rateLimited(let seconds?) = error { return min(.seconds(max(0, seconds)), maxRetryDelay) }
        return .seconds(1 << (attempt - 1))
    }
}
