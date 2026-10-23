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

    public static let maxAttempts = 3

    private let config: ExtractorConfig
    private let apiKey: @Sendable () -> String?
    private let transport: any HTTPTransport
    private let sleep: @Sendable (Duration) async -> Void

    public init(config: ExtractorConfig, apiKey: @escaping @Sendable () -> String?, transport: any HTTPTransport,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.config = config; self.apiKey = apiKey; self.transport = transport; self.sleep = sleep
    }

    public func extract(system: [SystemBlock], user: String) async throws(ExtractionError) -> Reply {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { throw .noKey }
        let request: URLRequest
        do { request = try makeRequest(key: key, system: system, user: user) } catch { throw .badRequest("\(error)") }

        var lastError: ExtractionError = .network("no attempt")
        for attempt in 1...Self.maxAttempts {
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
            if attempt < Self.maxAttempts { await sleep(Self.delay(for: lastError, attempt: attempt)) }
        }
        throw lastError
    }

    // MARK: - Request

    private func makeRequest(key: String, system: [SystemBlock], user: String) throws -> URLRequest {
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "system": system.map { block -> [String: Any] in
                var b: [String: Any] = ["type": "text", "text": block.text]
                if block.cached { b["cache_control"] = ["type": "ephemeral"] }
                return b
            },
            "messages": [["role": "user", "content": user]],
            "output_config": ["effort": config.effort, "format": ["type": "json_schema", "schema": ExtractorSchema.json]],
        ]
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

    private func parse(_ data: Data) throws(ExtractionError) -> Reply {
        let message: MessageResponse
        do { message = try JSONDecoder().decode(MessageResponse.self, from: data) } catch { throw .badOutput("response: \(error)") }
        switch message.stopReason {
        case "refusal": throw .refused(category: message.stopDetails?.category)
        case "max_tokens": throw .truncated
        default: break
        }
        let text = message.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        do {
            let output = try ExtractorOutput.decode(from: Data(text.utf8))
            return Reply(output: output, model: message.model, usage: message.usage)
        } catch {
            throw .badOutput("output: \(error)")
        }
    }

    private static func errorMessage(_ data: Data) -> String? {
        struct ErrorBody: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: "retry-after").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// 1 s, 2 s, 4 s, unless the server named a wait.
    static func delay(for error: ExtractionError, attempt: Int) -> Duration {
        if case .rateLimited(let seconds?) = error { return .seconds(seconds) }
        return .seconds(1 << (attempt - 1))
    }
}
