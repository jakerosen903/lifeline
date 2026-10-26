import Foundation

/// `InterviewerService` over the Messages API: one attempt, a short timeout, no fallback.
public struct AnthropicInterviewerService: InterviewerService {
    private let client: AnthropicMessagesClient
    private let systemPrompt: Result<String, ExtractionError>

    public init(config: ExtractorConfig = .interviewer, apiKey: @escaping @Sendable () -> String?,
                transport: any HTTPTransport = URLSessionTransport(timeout: 4)) {
        client = AnthropicMessagesClient(config: config, apiKey: apiKey, transport: transport)
        let name = "interviewer.\(config.version)"
        if let url = Bundle.module.url(forResource: name, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            systemPrompt = .success(text)
        } else {
            systemPrompt = .failure(.missingPrompt(name))
        }
    }

    public func reply(to request: InterviewerRequest) async throws(ExtractionError) -> InterviewerReply {
        let prompt = try systemPrompt.get()
        let user: String
        do { user = try request.userMessage() } catch { throw .badRequest("request: \(error)") }
        let raw = try await client.extract(system: [.init(text: prompt, cached: true)], user: user, schema: InterviewerReply.schema)
        do { return try JSONDecoder().decode(InterviewerReply.self, from: raw.data) } catch { throw .badOutput("reply: \(error)") }
    }
}
