import Foundation

/// JSON Schema for `ExtractorOutput`, sent as `output_config.format`. Structured outputs need
/// `additionalProperties: false` on every object, every property listed in `required`, and
/// nullable types for optional fields. Keep this in step with `ExtractorOutput`.
/// Computed, not stored: `[String: Any]` is not Sendable, so a stored static would be shared state.
public enum ExtractorSchema {
    public static var json: [String: Any] {
        object([
            "memories": array(memory),
            "mentions": array(mention),
            "flags": object([
                "disclosure": ["type": "string", "enum": DisclosureKind.allCases.map(\.rawValue)],
                "wants_to_stop": ["type": "boolean"],
                "wants_to_change_subject": ["type": "boolean"],
            ]),
        ])
    }

    private static var memory: [String: Any] {
        object([
            "ref": string,
            "kind": ["type": "string", "enum": MemoryKind.allCases.map(\.rawValue)],
            "title": string,
            "quote": string,
            "segment_span": object(["start_word": integer, "end_word": integer]),
            "people_refs": array(string),
            "place_text": nullableString,
            "anchors": array(object([
                "phrase": string,
                "relation": ["type": "string", "enum": AnchorRelation.allCases.map(\.rawValue)],
                "target_text": nullableString,
                "value": nullableString,
            ])),
            "same_as_memory_id": nullableString,
            "collection_hint": nullableString,
            "chapter_hint": nullableString,
            "confidence": number,
        ])
    }

    private static var mention: [String: Any] {
        object([
            "text": string,
            "kind": ["type": "string", "enum": MentionKind.allCases.map(\.rawValue)],
            "likely_alias_of_person_id": nullableString,
            "confidence": number,
            "relation_text": nullableString,
        ])
    }

    private static var string: [String: Any] { ["type": "string"] }
    private static var nullableString: [String: Any] { ["type": ["string", "null"]] }
    private static var integer: [String: Any] { ["type": "integer"] }
    private static var number: [String: Any] { ["type": "number"] }

    private static func array(_ items: [String: Any]) -> [String: Any] {
        ["type": "array", "items": items]
    }

    private static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
    }
}
