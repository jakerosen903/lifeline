import Foundation

/// The fixed system prompt, loaded from the versioned resource, and the per-segment user message.
public enum ExtractorPrompt {
    public enum Error: Swift.Error, Equatable {
        case missingPrompt(String)
    }

    /// The contents of `Prompts/extractor.<version>.md`.
    public static func system(version: String) throws -> String {
        guard let url = Bundle.module.url(forResource: "extractor.\(version)", withExtension: "md", subdirectory: "Prompts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Error.missingPrompt(version)
        }
        return text
    }

    /// The contents of `Prompts/reconciler.<version>.md` (M5).
    public static func reconciler(version: String) throws -> String {
        guard let url = Bundle.module.url(forResource: "reconciler.\(version)", withExtension: "md", subdirectory: "Prompts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Error.missingPrompt("reconciler.\(version)")
        }
        return text
    }
}
