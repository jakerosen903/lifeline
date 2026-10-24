import Foundation
import Testing
@testable import LifelineKit

@Test func reconcilerOutputRoundTripsAndSchemaMatches() throws {
    let json = Data(#"{"judgements":[{"a":"m1","b":"m2","verdict":"same_moment","confidence":0.9},{"a":"m1","b":"m3","verdict":"different","confidence":0.6}]}"#.utf8)
    let output = try JSONDecoder().decode(ReconcilerOutput.self, from: json)
    #expect(output.judgements.count == 2 && output.judgements[0].verdict == .sameMoment && output.judgements[1].verdict == .different)
    let again = try JSONDecoder().decode(ReconcilerOutput.self, from: try JSONEncoder().encode(output))
    #expect(again == output)
    let schema = ReconcilerSchema.json
    let items = (((schema["properties"] as? [String: Any])?["judgements"] as? [String: Any])?["items"] as? [String: Any]) ?? [:]
    let props = (items["properties"] as? [String: Any]) ?? [:]
    #expect(Set(props.keys) == ["a", "b", "verdict", "confidence"])
    #expect((props["verdict"] as? [String: Any])?["enum"] as? [String] == ["same_moment", "same_story", "different"])
    #expect(items["additionalProperties"] as? Bool == false && JSONSerialization.isValidJSONObject(schema))
    let prompt = try ExtractorPrompt.reconciler(version: "v1")
    #expect(prompt.contains("Prefer different when unsure") && prompt.contains("same_story"))
}

@Test func anthropicReconcileServiceSendsPairsAndTheReconcilerSchema() async throws {
    let body = APIBodies.success(text: #"{"judgements":[{"a":"m1","b":"m2","verdict":"same_story","confidence":0.8}]}"#)
    let transport = FakeHTTPTransport([.response(status: 200, body: body)])
    let service = AnthropicReconcileService(config: .default, apiKey: { "sk-ant-api03-test" }, transport: transport)
    let pair = PairRequest(id: "p1", a: PairSide(memoryID: "m1", title: "The blue door", quote: "the house had a blue door", rangeText: "1996"),
                           b: PairSide(memoryID: "m2", title: "Maya climbed it", quote: "my sister Maya climbed it", rangeText: nil))
    let response = try await service.judge([pair])
    #expect(response.output.judgements.first?.verdict == .sameStory && response.model == "claude-opus-5-5")
    let sent = try transport.body(of: 0)
    let format = ((sent["output_config"] as? [String: Any])?["format"] as? [String: Any]) ?? [:]
    #expect(((format["schema"] as? [String: Any])?["properties"] as? [String: Any])?["judgements"] != nil, "the reconciler's schema, not the extractor's")
    let messages = try #require(sent["messages"] as? [[String: Any]])
    #expect((messages[0]["content"] as? String)?.contains("the house had a blue door") == true)
    let system = try #require(sent["system"] as? [[String: Any]])
    #expect((system[0]["text"] as? String)?.contains("Prefer different when unsure") == true && system[0]["cache_control"] != nil)
}

@Test func scriptedReconcilerJudgesByTitle() async throws {
    let service = ScriptedReconcileService()
    func pair(_ id: String, _ a: String, _ b: String) -> PairRequest {
        PairRequest(id: id, a: PairSide(memoryID: "a-\(id)", title: a, quote: "", rangeText: nil), b: PairSide(memoryID: "b-\(id)", title: b, quote: "", rangeText: nil))
    }
    let out = try await service.judge([pair("1", "The blue door", "the blue door"), pair("2", "The blue door", "Maya climbed it"), pair("3", "The canal", "The blue door")]).output
    #expect(out.judgements.map(\.verdict) == [.sameMoment, .sameStory, .different])
    #expect(out.judgements.map(\.a) == ["a-1", "a-2", "a-3"] && out.judgements.map(\.b) == ["b-1", "b-2", "b-3"])
}
