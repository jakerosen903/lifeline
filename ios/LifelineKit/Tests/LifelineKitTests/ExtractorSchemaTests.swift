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

@Test func v2FlagsDecodeAsPast() throws {
    let old = try CandidatePayload.decode(Flags.self, from: #"{"serious_disclosure":true,"wants_to_stop":false,"wants_to_change_subject":false}"#)
    #expect(old.disclosure == .past && old.seriousDisclosure && old.isHeavy)
    let new = try CandidatePayload.decode(Flags.self, from: #"{"disclosure":"present","wants_to_stop":false,"wants_to_change_subject":true}"#)
    #expect(new.disclosure == .present && new.isHeavy && new.isAnySet)
    let quiet = try CandidatePayload.decode(Flags.self, from: #"{"disclosure":"none","wants_to_stop":false,"wants_to_change_subject":false}"#)
    #expect(!quiet.isHeavy && !quiet.isAnySet)
}

@Test func schemaHasTheDisclosureEnum() throws {
    let flags = (((ExtractorSchema.json["properties"] as? [String: Any])?["flags"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
    #expect((flags["disclosure"] as? [String: Any])?["enum"] as? [String] == ["none", "past", "present"])
    #expect(flags["serious_disclosure"] == nil)
    let text = try ExtractorPrompt.system(version: "v3")
    #expect(text.contains("`present`") && text.contains("`past`"))
    let v4 = try ExtractorPrompt.system(version: "v4")
    #expect(v4.contains("Prefer null when unsure") && v4.contains("`related`"), "v4 asks for same-as on retellings across recordings")
}

@Test func configDefaultsMatchTheSpec() {
    let c = ExtractorConfig.default
    #expect(c.model == "claude-opus-5-5" && c.effort == "low" && c.maxTokens == 4096 && c.version == "v6")
    #expect(c.betas.contains("server-side-fallback-2026-07-01"))
}

@Test func v5SchemaNamesTheNewFields() {
    let schema = ExtractorSchema.json
    let memory = (((schema["properties"] as? [String: Any])?["memories"] as? [String: Any])?["items"] as? [String: Any]) ?? [:]
    let props = (memory["properties"] as? [String: Any]) ?? [:]
    #expect((props["same_as_memory_ids"] as? [String: Any])?["type"] as? String == "array")
    #expect(props["same_as_memory_id"] == nil)
    for key in ["continues_candidate_id", "story_ref", "story_title_hint"] {
        #expect((props[key] as? [String: Any])?["type"] as? [String] == ["string", "null"], Comment(rawValue: key))
    }
    #expect(props["extra_spans"] == nil, "app-written, never asked of the model")
    let required = Set((memory["required"] as? [String]) ?? [])
    #expect(required.isSuperset(of: ["same_as_memory_ids", "continues_candidate_id", "story_ref", "story_title_hint"]))
}

// The API refuses a schema with more than 16 union-typed parameters (type arrays or anyOf). The
// handles and hints are plain strings where "" means none, so the count stays well under.
@Test func schemaStaysUnderTheUnionLimit() {
    var unions = 0
    func walk(_ node: Any) {
        if let dict = node as? [String: Any] {
            if dict["type"] is [Any] || dict["anyOf"] != nil { unions += 1 }
            dict.values.forEach(walk)
        } else if let array = node as? [Any] { array.forEach(walk) }
    }
    walk(ExtractorSchema.json)
    #expect(unions <= 12, "\(unions) union-typed parameters; the API's limit is 16")
}

@Test func emptyHandlesAndHintsDecodeAsNone() throws {
    let json = """
    {"memories":[{"ref":"m1","kind":"fact","title":"The fence was white","quote":"the fence was white","segment_span":{"start_word":0,"end_word":3},
      "people_refs":[],"place_text":null,"anchors":[],"same_as_memory_ids":[],"continues_candidate_id":null,"story_ref":null,"story_title_hint":null,
      "collection_hint":null,"chapter_hint":null,"confidence":0.9,"entity_refs":[],"about_ref":"","domain_hint":""}],
     "mentions":[{"text":"the fence","kind":"thing","likely_alias_of_person_id":null,"confidence":0.9,"relation_text":null,"ref":"","likely_entity_id":null,"title":"","domain_hint":""}],
     "flags":{"disclosure":"none","wants_to_stop":false,"wants_to_change_subject":false}}
    """
    let out = try ExtractorOutput.decode(from: Data(json.utf8))
    #expect(out.memories[0].aboutRef == nil && out.memories[0].domainHint == nil)
    #expect(out.mentions[0].ref == nil && out.mentions[0].title == nil && out.mentions[0].domainHint == nil)
}
