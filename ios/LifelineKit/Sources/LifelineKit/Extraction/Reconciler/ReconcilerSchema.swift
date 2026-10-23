import Foundation

/// JSON Schema for `ReconcilerOutput`, same rules as `ExtractorSchema`.
public enum ReconcilerSchema {
    public static var json: [String: Any] {
        object(["judgements": ["type": "array", "items": object([
            "a": ["type": "string"],
            "b": ["type": "string"],
            "verdict": ["type": "string", "enum": [PairVerdict.sameMoment, .sameStory, .different].map(\.rawValue)],
            "confidence": ["type": "number"],
        ])]])
    }

    private static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
    }
}
