import Foundation
import Testing
@testable import LifelineKit

@Test func schemaForbidsExtraPropertiesEverywhere() throws {
    var objects = 0
    func walk(_ node: Any) {
        guard let dict = node as? [String: Any] else {
            if let array = node as? [Any] { array.forEach(walk) }
            return
        }
        if dict["type"] as? String == "object" {
            objects += 1
            #expect(dict["additionalProperties"] as? Bool == false, "object without additionalProperties: false: \(dict.keys.sorted())")
            let properties = (dict["properties"] as? [String: Any]) ?? [:]
            let required = Set((dict["required"] as? [String]) ?? [])
            #expect(required == Set(properties.keys), "required != properties for \(properties.keys.sorted())")
        }
        dict.values.forEach(walk)
    }
    walk(ExtractorSchema.json)
    #expect(objects >= 6)
    #expect(JSONSerialization.isValidJSONObject(ExtractorSchema.json))
}

@Test func sampleOutputDecodesWithSpecKeys() throws {
    let url = try #require(Bundle.module.url(forResource: "extractor-output-garden", withExtension: "json", subdirectory: "Fixtures"))
    let output = try ExtractorOutput.decode(from: try Data(contentsOf: url))
    #expect(output.memories.count == 1)
    #expect(output.memories[0].title == "The pomegranate tree")
    #expect(output.memories[0].peopleRefs == ["my mother"])
    #expect(output.memories[0].segmentSpan == WordSpan(startWord: 0, endWord: 8))
    #expect(output.memories[0].anchors.first?.relation == .age)
    #expect(output.mentions.count == 1 && output.mentions[0].kind == .person)
    #expect(output.memories[0].kind == .event)
    #expect(output.mentions[0].relationText == "my mother")
    let schema = ExtractorSchema.json
    let memoryProps = ((((schema["properties"] as? [String: Any])?["memories"] as? [String: Any])?["items"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
    #expect((memoryProps["kind"] as? [String: Any])?["enum"] as? [String] == MemoryKind.allCases.map(\.rawValue))
    let mentionProps = ((((schema["properties"] as? [String: Any])?["mentions"] as? [String: Any])?["items"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
    #expect(mentionProps["relation_text"] != nil)
    #expect(output.flags == Flags(seriousDisclosure: false, wantsToStop: false, wantsToChangeSubject: false))
}

@Test func promptV1LoadsAndNamesTheRules() throws {
    let text = try ExtractorPrompt.system(version: "v1")
    #expect(text.contains("Extract only what is said"))
    #expect(text.contains("8 words"))
    #expect(throws: ExtractorPrompt.Error.missingPrompt("v9")) { try ExtractorPrompt.system(version: "v9") }
}

@Test func configDefaultsMatchTheSpec() {
    let c = ExtractorConfig.default
    #expect(c.model == "claude-opus-5-5" && c.effort == "low" && c.maxTokens == 4096 && c.version == "v2")
    #expect(c.betas.contains("server-side-fallback-2026-07-01"))
}
