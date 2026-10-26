import Foundation
import Testing
@testable import LifelineKit

private func client(_ transport: FakeHTTPTransport, key: String? = "sk-ant-api03-test", sleeper: SleepRecorder = SleepRecorder()) -> AnthropicMessagesClient {
    AnthropicMessagesClient(config: .default, apiKey: { key }, transport: transport, sleep: { await sleeper.sleep($0) })
}

@Test func requestCarriesTheSpecShape() async throws {
    let transport = FakeHTTPTransport([.response(status: 200, body: APIBodies.success())])
    _ = try await client(transport).extract(system: [.init(text: "SYSTEM", cached: true)], user: "USER")
    let body = try transport.body(of: 0)
    #expect(body["model"] as? String == "claude-opus-5-5")
    #expect(body["max_tokens"] as? Int == 4096)
    #expect(body["fallbacks"] as? String == "default")
    #expect(body["thinking"] == nil)
    let outputConfig = try #require(body["output_config"] as? [String: Any])
    #expect(outputConfig["effort"] as? String == "low")
    let format = try #require(outputConfig["format"] as? [String: Any])
    #expect(format["type"] as? String == "json_schema")
    #expect((format["schema"] as? [String: Any])?["type"] as? String == "object")
    let system = try #require(body["system"] as? [[String: Any]])
    #expect(system[0]["text"] as? String == "SYSTEM")
    #expect((system[0]["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages[0]["role"] as? String == "user" && messages[0]["content"] as? String == "USER")
    let request = transport.requests[0]
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-api03-test")
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta")?.contains("server-side-fallback-2026-07-01") == true)
    #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
    #expect(request.httpMethod == "POST" && request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
}

@Test func parsesTextBlockIntoOutput() async throws {
    let transport = FakeHTTPTransport([.response(status: 200, body: APIBodies.success())])
    let result = try await client(transport).extract(system: [.init(text: "S", cached: true)], user: "U")
    #expect(result.output.memories.first?.title == "The pomegranate tree")
    #expect(result.model == "claude-opus-5-5")
    #expect(result.usage.cacheReadInputTokens == 900 && result.usage.inputTokens == 1200)
}

@Test func refusalIsNotParsed() async throws {
    let transport = FakeHTTPTransport([.response(status: 200, body: APIBodies.refusal)])
    await #expect(throws: ExtractionError.refused(category: "cyber")) {
        try await client(transport).extract(system: [.init(text: "S", cached: true)], user: "U")
    }
}

@Test func maxTokensIsTruncated() async throws {
    let transport = FakeHTTPTransport([.response(status: 200, body: APIBodies.truncated)])
    await #expect(throws: ExtractionError.truncated) {
        try await client(transport).extract(system: [.init(text: "S", cached: true)], user: "U")
    }
}

@Test func missingKeyFailsBeforeAnyRequest() async throws {
    let transport = FakeHTTPTransport([.response(status: 200, body: APIBodies.success())])
    await #expect(throws: ExtractionError.noKey) {
        try await client(transport, key: nil).extract(system: [.init(text: "S", cached: true)], user: "U")
    }
    await #expect(throws: ExtractionError.noKey) {
        try await client(transport, key: "  ").extract(system: [.init(text: "S", cached: true)], user: "U")
    }
    #expect(transport.requests.isEmpty)
}

@Test func unauthorizedDoesNotRetry() async throws {
    let transport = FakeHTTPTransport([.response(status: 401, body: APIBodies.apiError), .response(status: 200, body: APIBodies.success())])
    await #expect(throws: ExtractionError.unauthorized) {
        try await client(transport).extract(system: [.init(text: "S", cached: true)], user: "U")
    }
    #expect(transport.requests.count == 1)
}

@Test func rateLimitRetriesThenGivesUp() async throws {
    let transport = FakeHTTPTransport([.response(status: 429, body: APIBodies.apiError), .response(status: 429, body: APIBodies.apiError), .response(status: 429, body: APIBodies.apiError)])
    let sleeper = SleepRecorder()
    await #expect(throws: ExtractionError.rateLimited(retryAfterSeconds: nil)) {
        try await client(transport, sleeper: sleeper).extract(system: [.init(text: "S", cached: true)], user: "U")
    }
    #expect(transport.requests.count == 3)
    #expect(sleeper.durations == [.seconds(1), .seconds(2)])
}

@Test func retryAfterHeaderWins() async throws {
    let transport = FakeHTTPTransport([.response(status: 429, body: APIBodies.apiError, headers: ["retry-after": "5"]), .response(status: 200, body: APIBodies.success())])
    let sleeper = SleepRecorder()
    _ = try await client(transport, sleeper: sleeper).extract(system: [.init(text: "S", cached: true)], user: "U")
    #expect(sleeper.durations == [.seconds(5)])
}

@Test func networkErrorRetriesAndSucceeds() async throws {
    let transport = FakeHTTPTransport([.error(URLError(.notConnectedToInternet)), .response(status: 200, body: APIBodies.success())])
    let result = try await client(transport).extract(system: [.init(text: "S", cached: true)], user: "U")
    #expect(result.output.memories.count == 1 && transport.requests.count == 2)
}

@Test func serverErrorsRetryAndOverloadedToo() async throws {
    let transport = FakeHTTPTransport([.response(status: 529, body: APIBodies.apiError), .response(status: 500, body: APIBodies.apiError), .response(status: 500, body: APIBodies.apiError)])
    await #expect(throws: ExtractionError.server(status: 500)) {
        try await client(transport).extract(system: [.init(text: "S", cached: true)], user: "U")
    }
    #expect(transport.requests.count == 3)
}

@Test func badJSONInTextIsBadOutput() async throws {
    let transport = FakeHTTPTransport([.response(status: 200, body: APIBodies.success(text: "not json"))])
    do {
        _ = try await client(transport).extract(system: [.init(text: "S", cached: true)], user: "U")
        Issue.record("expected badOutput")
    } catch ExtractionError.badOutput { } catch { Issue.record("wrong error \(error)") }
}

@Test func profileFreeTextIsASecondSystemBlockWithoutCache() async throws {
    let transport = FakeHTTPTransport([.response(status: 200, body: APIBodies.success())])
    let service = AnthropicExtractionService(config: .default, apiKey: { "sk-ant-api03-test" }, transport: transport)
    let segment = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "the garden had a pomegranate tree", status: .pending)
    let packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: "I grew up in Fresno", stage: "open")
    let response = try await service.extract(ExtractionRequest(segmentID: segment.id, segmentText: segment.text, words: segment.text.split(separator: " ").map(String.init), packet: packet))
    #expect(response.version == "v6")
    let system = try #require(try transport.body(of: 0)["system"] as? [[String: Any]])
    #expect(system.count == 2)
    #expect((system[0]["text"] as? String)?.contains("Extract only what is said") == true)
    #expect(system[0]["cache_control"] != nil)
    #expect((system[1]["text"] as? String)?.contains("I grew up in Fresno") == true)
    #expect(system[1]["cache_control"] == nil)
    let user = try #require((try transport.body(of: 0)["messages"] as? [[String: Any]])?[0]["content"] as? String)
    #expect(user.contains("0:the"))
}

@Test func retryAfterIsCapped() async throws {
    let transport = FakeHTTPTransport([.response(status: 429, body: APIBodies.apiError, headers: ["retry-after": "600"]), .response(status: 200, body: APIBodies.success())])
    let sleeper = SleepRecorder()
    _ = try await client(transport, sleeper: sleeper).extract(system: [.init(text: "S", cached: true)], user: "U")
    #expect(sleeper.durations == [AnthropicMessagesClient.maxRetryDelay])
    #expect(AnthropicMessagesClient.maxRetryDelay <= .seconds(10))
}
