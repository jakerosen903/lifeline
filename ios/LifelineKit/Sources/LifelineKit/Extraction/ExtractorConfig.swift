import Foundation

/// Everything about the model call that is configuration, not code.
public struct ExtractorConfig: Sendable, Equatable {
    public var model: String
    public var effort: String
    public var maxTokens: Int
    /// Names the prompt file `extractor.<version>.md` and is stored on every candidate.
    public var version: String
    public var apiVersion: String
    public var betas: [String]
    public var endpoint: URL
    /// Requests per call, retries included. The extractor retries; the interviewer must not hold a turn.
    public var maxAttempts: Int
    /// Sends `"thinking": {"type": "disabled"}`. Off keeps the extractor's request as it was.
    public var thinkingDisabled: Bool

    public init(model: String = "claude-opus-5-5", effort: String = "low", maxTokens: Int = 4096, version: String = "v6",
                apiVersion: String = "2023-06-01", betas: [String] = ["server-side-fallback-2026-07-01"],
                endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
                maxAttempts: Int = 3, thinkingDisabled: Bool = false) {
        self.model = model; self.effort = effort; self.maxTokens = maxTokens; self.version = version
        self.apiVersion = apiVersion; self.betas = betas; self.endpoint = endpoint
        self.maxAttempts = maxAttempts; self.thinkingDisabled = thinkingDisabled
    }

    public static let `default` = ExtractorConfig()

    /// The interviewer's fast call. Haiku 5.5 has no server-side fallback, so no beta and no `fallbacks`.
    public static let interviewer = ExtractorConfig(model: "claude-haiku-5-5", effort: "low", maxTokens: 512, version: "v1",
                                                    betas: [], maxAttempts: 1, thinkingDisabled: true)
}
