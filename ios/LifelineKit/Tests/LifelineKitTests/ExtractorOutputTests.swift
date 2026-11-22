import Foundation
import Testing
@testable import LifelineKit

private func memoryJSON(_ extra: String) -> Data {
    Data("""
    {"ref":"m1","kind":"event","title":"T","quote":"q","segment_span":{"start_word":0,"end_word":1},"people_refs":[],"place_text":null,
     "anchors":[],"collection_hint":null,"chapter_hint":null,"confidence":0.9\(extra)}
    """.utf8)
}

@Test func v5OutputDecodesSingularAndListForms() throws {
    let singular = try JSONDecoder().decode(MemoryOut.self, from: memoryJSON(#","same_as_memory_id":"m1""#))
    #expect(singular.sameAsMemoryIDs == ["m1"] && singular.sameAsMemoryID == "m1")
    let list = try JSONDecoder().decode(MemoryOut.self, from: memoryJSON(#","same_as_memory_ids":["a","b"]"#))
    #expect(list.sameAsMemoryIDs == ["a", "b"] && list.sameAsMemoryID == "a")
    let bare = try JSONDecoder().decode(MemoryOut.self, from: memoryJSON(""))
    #expect(bare.sameAsMemoryIDs.isEmpty && bare.continuesCandidateID == nil && bare.storyRef == nil && bare.storyTitleHint == nil && bare.extraSpans.isEmpty)
    let full = try JSONDecoder().decode(MemoryOut.self, from: memoryJSON(#","same_as_memory_ids":["a"],"continues_candidate_id":"c1","story_ref":"s1","story_title_hint":"The door summer","extra_spans":[{"segment_id":"g2","start_word":0,"end_word":3}]"#))
    #expect(full.continuesCandidateID == "c1" && full.storyRef == "s1" && full.storyTitleHint == "The door summer")
    #expect(full.extraSpans == [ExtraSpan(segmentID: "g2", startWord: 0, endWord: 3)])
    let encoded = String(decoding: try JSONEncoder().encode(full), as: UTF8.self)
    #expect(encoded.contains(#""same_as_memory_ids":["a"]"#) && !encoded.contains("same_as_memory_id\""))
    let again = try JSONDecoder().decode(MemoryOut.self, from: Data(encoded.utf8))
    #expect(again == full)
}

// MARK: - People with handles (v8)

@Test func twoPeopleWithOneNameDecodeWithTwoHandles() throws {
    let url = try #require(Bundle.module.url(forResource: "extractor-output-two-robyns", withExtension: "json", subdirectory: "Fixtures"))
    let output = try ExtractorOutput.decode(from: try Data(contentsOf: url))
    #expect(output.people == [PersonOut(handle: "p1", saidName: "Robyn", relationText: "from work", personID: nil),
                              PersonOut(handle: "p2", saidName: "Robyn", relationText: "my cousin", personID: nil)])
    #expect(output.memories.map(\.personHandles) == [["p1"], ["p2"]])
    #expect(output.memories.allSatisfy { $0.peopleRefs.isEmpty && $0.handlePeople.isEmpty })
    #expect(output.mentions.map(\.handle) == ["p1", "p2"])
    let again = try ExtractorOutput.decode(from: try output.encoded())
    #expect(again == output)
}

@Test func aV6PayloadDecodesWithNoPeopleAndNoHandles() throws {
    let json = """
    {"memories":[{"ref":"m1","kind":"event","title":"T","quote":"q","segment_span":{"start_word":0,"end_word":1},"people_refs":["Maya"],
      "place_text":null,"anchors":[],"same_as_memory_ids":[],"continues_candidate_id":null,"story_ref":null,"story_title_hint":null,
      "collection_hint":null,"chapter_hint":null,"confidence":0.9,"entity_refs":[],"about_ref":"","domain_hint":""}],
     "mentions":[{"text":"Maya","kind":"person","likely_alias_of_person_id":"person-7","confidence":0.9,"relation_text":"my sister","ref":"","likely_entity_id":null,"title":"","domain_hint":""}],
     "flags":{"disclosure":"none","wants_to_stop":false,"wants_to_change_subject":false}}
    """
    let out = try ExtractorOutput.decode(from: Data(json.utf8))
    #expect(out.people.isEmpty)
    #expect(out.memories[0].personHandles.isEmpty && out.memories[0].handlePeople.isEmpty && out.memories[0].peopleRefs == ["Maya"])
    #expect(out.mentions[0].handle == nil && out.mentions[0].relationText == "my sister")
}

@Test func emptyPersonFieldsAndMentionHandleDecodeAsNone() throws {
    let person = try JSONDecoder().decode(PersonOut.self, from: Data(#"{"handle":"p1","said_name":"Robyn","relation_text":"","person_id":" "}"#.utf8))
    #expect(person == PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: nil))
    let mention = try JSONDecoder().decode(MentionOut.self, from: Data(#"{"text":"Robyn","kind":"person","confidence":0.9,"handle":""}"#.utf8))
    #expect(mention.handle == nil)
}

@Test func appWrittenHandlePeopleRoundTripOnAMemory() throws {
    var memory = try JSONDecoder().decode(MemoryOut.self, from: memoryJSON(#","person_handles":["p1"]"#))
    memory.handlePeople = [PersonOut(handle: "p1", saidName: "Robyn", relationText: "from work", personID: "person-3")]
    let again = try JSONDecoder().decode(MemoryOut.self, from: try JSONEncoder().encode(memory))
    #expect(again == memory && again.personHandles == ["p1"])
}

// Final review M8: a handle compares exactly elsewhere, so the decoder trims it, as it trims a mention's handle.
@Test func handlesAreTrimmedAtDecode() throws {
    let person = try JSONDecoder().decode(PersonOut.self, from: Data(#"{"handle":" p1 ","said_name":"Robyn"}"#.utf8))
    #expect(person.handle == "p1")
    let memory = try JSONDecoder().decode(MemoryOut.self, from: memoryJSON(#","person_handles":[" p1","p2 "],"about_ref":" p1 ""#))
    #expect(memory.personHandles == ["p1", "p2"])
    #expect(memory.aboutRef == "p1", "about_ref was already trimmed at decode, so every reader compares it trimmed")
}
