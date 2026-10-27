import Foundation
import Testing
@testable import LifelineKit

private func service(_ transport: FakeHTTPTransport, key: String? = "sk-ant-api03-test") -> AnthropicInterviewerService {
    AnthropicInterviewerService(config: .interviewer, apiKey: { key }, transport: transport)
}

private let request = InterviewerRequest(segments: ["we had a blue door", "it was a small house"], opening: "Tell me about home.",
                                         stage: .open, recentTurns: ["Tell me about home."])

private func body(_ json: String) -> FakeHTTPTransport {
    FakeHTTPTransport([.response(status: 200, body: APIBodies.success(text: json, model: "claude-haiku-5-5"))])
}

@Test func aReplyDecodes() async throws {
    let json = #"{"kind":"reflection","text":"A blue door.","asked_about_app":false,"disclosure":"none","wants_to_stop":false}"#
    let reply = try await service(body(json)).reply(to: request)
    #expect(reply == InterviewerReply(kind: .reflection, text: "A blue door.", askedAboutApp: false, disclosure: .none, wantsToStop: false))
    #expect(reply.check == SafetyCheck(disclosure: .none, wantsToStop: false))
}

@Test func aNullTextAndAFlaggedCheckDecode() async throws {
    let json = #"{"kind":"none","text":null,"asked_about_app":true,"disclosure":"past","wants_to_stop":true}"#
    let reply = try await service(body(json)).reply(to: request)
    #expect(reply.kind == .none && reply.text == nil && reply.askedAboutApp)
    #expect(reply.check == SafetyCheck(disclosure: .past, wantsToStop: true))
}

@Test func aMissingKeyIsNoKey() async throws {
    let transport = FakeHTTPTransport([])
    await #expect(throws: ExtractionError.noKey) { try await service(transport, key: nil).reply(to: request) }
    #expect(transport.requests.isEmpty)
}

@Test func aMissingJSONKeyIsBadOutput() async throws {
    let json = #"{"kind":"reflection","text":"A blue door.","asked_about_app":false,"disclosure":"none"}"#
    do {
        _ = try await service(body(json)).reply(to: request)
        Issue.record("expected badOutput")
    } catch ExtractionError.badOutput { } catch { Issue.record("wrong error \(error)") }
}

@Test func theUserMessageIsSortedJSON() throws {
    let message = try request.userMessage()
    let object = try #require(try JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])
    #expect(object["stage"] as? String == "open")
    #expect(object["segments"] as? [String] == ["we had a blue door", "it was a small house"])
    #expect(object["opening"] as? String == "Tell me about home.")
    #expect(object["recent_turns"] as? [String] == ["Tell me about home."])
    let keys = ["opening", "recent_turns", "segments", "stage"].map { message.range(of: "\"\($0)\"")!.lowerBound }
    #expect(keys == keys.sorted())
}

@Test func theSystemPromptIsTheBundledV1() async throws {
    let transport = body(#"{"kind":"none","text":null,"asked_about_app":false,"disclosure":"none","wants_to_stop":false}"#)
    _ = try await service(transport).reply(to: request)
    let system = try #require(try transport.body(of: 0)["system"] as? [[String: Any]])
    let text = try #require(system[0]["text"] as? String)
    #expect(text.contains("Never answer a question about the person's life."))
    #expect(text.contains("When `stage` is `windDown`, return `none`."))
    #expect(text.contains("narrates harm that happened"))
}

@Test func theScriptedServiceReflectsTheLastFourWords() async throws {
    let scripted = ScriptedInterviewerService(disclosureOn: [1])
    let first = try await scripted.reply(to: .init(segments: ["we had a blue door in the house"], opening: "", stage: .open, recentTurns: []))
    #expect(first.kind == .reflection && first.text == "Door in the house")
    #expect(first.disclosure == .none)
    let second = try await scripted.reply(to: .init(segments: ["x y"], opening: "", stage: .open, recentTurns: []))
    #expect(second.disclosure == .past)
    let empty = try await scripted.reply(to: .init(segments: [], opening: "", stage: .open, recentTurns: []))
    #expect(empty.kind == .none && empty.text == nil)
}
