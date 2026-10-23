import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage

/// Apple's on-device English sentence embedding. No network, no key. Nil when the asset is
/// not available on this device or platform. The model is loaded once per process: loading it
/// per sentence would make a backfill of N memories N asset loads.
public struct NLSentenceEmbedder: SentenceEmbedder {
    public let model = "nl-sentence-en"

    public init() {}

    public func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let embedding = Self.shared.embedding(), let vector = embedding.vector(for: trimmed) else { return nil }
        return vector.map { Float($0) }
    }

    // MARK: - One load per process

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded = false
        private var value: NLEmbedding?
        private(set) var loads = 0

        func embedding() -> NLEmbedding? {
            lock.lock(); defer { lock.unlock() }
            if !loaded {
                loaded = true
                loads += 1
                value = NLEmbedding.sentenceEmbedding(for: .english)
            }
            return value
        }

        func reset() { lock.lock(); loaded = false; value = nil; loads = 0; lock.unlock() }
    }

    private static let shared = Cache()

    /// How many times the asset was loaded in this process. Tests only.
    public static var loadCount: Int { shared.loads }
    public static func resetLoadCountForTesting() { shared.reset() }
}
#endif
