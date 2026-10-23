import Foundation

/// A scene prompt from the bank. The id is what the prompt log remembers; the text is the owner's to edit.
public struct ScenePrompt: Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String

    public init(id: String, text: String) { self.id = id; self.text = text }
}

/// Loads `Prompts/openers.<version>.md`: one prompt per line as `id: text`; `#` lines are comments.
public enum PromptBank {
    public enum Error: Swift.Error, Equatable {
        case missingBank(String)
    }

    public static func load(version: String = "v1") throws -> [ScenePrompt] {
        guard let url = Bundle.module.url(forResource: "openers.\(version)", withExtension: "md", subdirectory: "Prompts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Error.missingBank(version)
        }
        return parse(text)
    }

    static func parse(_ text: String) -> [ScenePrompt] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { rawLine -> ScenePrompt? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { return nil }
            let id = line[..<colon].trimmingCharacters(in: .whitespaces)
            let prompt = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !prompt.isEmpty, seen.insert(id).inserted else { return nil }
            return ScenePrompt(id: id, text: prompt)
        }
    }
}
