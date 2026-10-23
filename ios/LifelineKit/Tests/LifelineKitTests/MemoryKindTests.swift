import Foundation
import Testing
@testable import LifelineKit

@Test func kindsHaveCardLabels() {
    #expect(MemoryKind.event.cardLabel == "Sounds like a memory")
    #expect(MemoryKind.fact.cardLabel == "Something about your life")
    #expect(MemoryKind.feeling.cardLabel == "Something you felt")
    #expect(MemoryKind.goal.cardLabel == "Something you wanted")
    #expect(MemoryKind.other.cardLabel == "Sounds like a memory")
}

@Test func olderPayloadsWithoutKindStillDecode() throws {
    let json = """
    {"ref":"m","title":"T","quote":"q","segment_span":{"start_word":0,"end_word":0},"people_refs":[],"place_text":null,"anchors":[],"same_as_memory_id":null,"collection_hint":null,"chapter_hint":null,"confidence":0.5}
    """
    let out = try CandidatePayload.decode(MemoryOut.self, from: json)
    #expect(out.kind == nil && out.kindOrDefault == .other)
}

@Test func promptV2IsTheDefaultAndNamesKindsAndRelations() throws {
    #expect(ExtractorConfig.default.version == "v2")
    let text = try ExtractorPrompt.system(version: "v2")
    #expect(text.contains("`kind`") && text.contains("fact") && text.contains("relation_text"))
    #expect(throws: Never.self) { try ExtractorPrompt.system(version: "v1") }
}
