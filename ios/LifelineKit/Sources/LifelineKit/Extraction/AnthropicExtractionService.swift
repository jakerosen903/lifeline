import Foundation

/// `ExtractionService` over the Messages API. The fixed prompt is the cached system block;
/// the owner's free text is a second, uncached block so editing it never invalidates the cache.
public struct AnthropicExtractionService: ExtractionService {
    public let version: String
    private let client: AnthropicMessagesClient
    private let systemPrompt: Result<String, ExtractionError>

    public init(config: ExtractorConfig = .default, apiKey: @escaping @Sendable () -> String?, transport: any HTTPTransport = URLSessionTransport()) {
        version = config.version
        client = AnthropicMessagesClient(config: config, apiKey: apiKey, transport: transport)
        do { systemPrompt = .success(try ExtractorPrompt.system(version: config.version)) }
        catch { systemPrompt = .failure(.missingPrompt(config.version)) }
    }

    public func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse {
        let prompt = try systemPrompt.get()
        var system = [AnthropicMessagesClient.SystemBlock(text: prompt, cached: true)]
        if let free = request.packet.profileFreeText?.trimmingCharacters(in: .whitespacesAndNewlines), !free.isEmpty {
            system.append(.init(text: "About the person, in their own words: \(free)", cached: false))
        }
        let user: String
        do { user = try ExtractorPrompt.userMessage(segmentText: request.segmentText, words: request.words, packet: request.packet) }
        catch { throw .badRequest("packet: \(error)") }
        let reply = try await client.extract(system: system, user: user)
        return ExtractionResponse(output: reply.output, version: version, model: reply.model, usage: reply.usage)
    }
}
