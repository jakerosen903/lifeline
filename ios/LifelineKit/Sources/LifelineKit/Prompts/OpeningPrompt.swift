import Foundation

/// What a session opens with: a question from the owner's own open threads, or a scene prompt.
public enum OpeningPrompt: Equatable, Sendable {
    case curiosity(CuriosityItem, text: String)
    case scene(ScenePrompt)

    public var text: String {
        switch self {
        case .curiosity(_, let text): text
        case .scene(let prompt): prompt.text
        }
    }

    /// What the prompt log records.
    public var logID: String {
        switch self {
        case .curiosity(let item, _): "curiosity:\(item.id.rawValue)"
        case .scene(let prompt): prompt.id
        }
    }
}

public struct Opening: Equatable, Sendable {
    public var main: OpeningPrompt
    public var alternates: [OpeningPrompt]

    public init(main: OpeningPrompt, alternates: [OpeningPrompt]) { self.main = main; self.alternates = alternates }
}

/// Pure. The open question with the biggest payoff leads, unless it opened a session in the
/// last week; otherwise the first never-used scene prompt, and once every prompt has been used,
/// the least recently used. Alternates are the next three by the same order, never the main.
public enum OpeningChooser {
    public static let curiosityCooldown: TimeInterval = 7 * 86_400

    public static func choose(curiosity: [CuriosityItem], bank: [ScenePrompt], lastUsed: [String: Date], now: Date,
                              alternateCount: Int = 3) -> Opening {
        let scenes = orderedScenes(bank, lastUsed: lastUsed)
        let lead = curiosity
            .filter { $0.status == .open }
            .sorted { a, b in
                if a.payoffCount != b.payoffCount { return a.payoffCount > b.payoffCount }
                // A dated question is never outranked by an entity question (M7).
                if (a.kind == .unresolvedAnchor) != (b.kind == .unresolvedAnchor) { return a.kind == .unresolvedAnchor }
                return a.text < b.text
            }
            .first { item in
                guard let used = lastUsed["curiosity:\(item.id.rawValue)"] else { return true }
                return now.timeIntervalSince(used) >= curiosityCooldown
            }
        if let lead {
            return Opening(main: .curiosity(lead, text: phrase(for: lead)), alternates: scenes.prefix(alternateCount).map(OpeningPrompt.scene))
        }
        guard let first = scenes.first else {
            return Opening(main: .scene(ScenePrompt(id: "house", text: "Tell me about the house you grew up in.")), alternates: [])
        }
        return Opening(main: .scene(first), alternates: scenes.dropFirst().prefix(alternateCount).map(OpeningPrompt.scene))
    }

    /// Never used first, in bank order; then by oldest use.
    static func orderedScenes(_ bank: [ScenePrompt], lastUsed: [String: Date]) -> [ScenePrompt] {
        bank.enumerated().sorted { a, b in
            switch (lastUsed[a.element.id], lastUsed[b.element.id]) {
            case (nil, nil): return a.offset < b.offset
            case (nil, _?): return true
            case (_?, nil): return false
            case (let x?, let y?): return x != y ? x < y : a.offset < b.offset
            }
        }.map(\.element)
    }

    /// A phrase the owner said becomes "You mentioned “…”. Tell me about that."; a title reads "Tell me about …".
    static func phrase(for item: CuriosityItem) -> String {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.kind.isEntityQuestion { return text }
        let looksLikeTitle = text.first?.isUppercase == true && text.split(separator: " ").count <= 6
        return looksLikeTitle ? "Tell me about \(text)." : "You mentioned “\(text)”. Tell me about that."
    }
}
