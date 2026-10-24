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
