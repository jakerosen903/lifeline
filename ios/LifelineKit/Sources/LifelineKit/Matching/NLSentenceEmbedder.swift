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
        // `vector(for:)` is not documented thread-safe; the backfill, the extraction actor and the
        // main actor all call it, so the lock covers the call, not only the load.
        guard !trimmed.isEmpty, let vector = Self.shared.vector(for: trimmed) else { return nil }
        return vector.map { Float($0) }
    }

    // MARK: - One load per process

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded = false
        private var value: NLEmbedding?
        private(set) var loads = 0

        func vector(for text: String) -> [Double]? {
            lock.lock(); defer { lock.unlock() }
            if !loaded {
                loaded = true
                loads += 1
                value = NLEmbedding.sentenceEmbedding(for: .english)
            }
            return value?.vector(for: text)
        }

        func reset() { lock.lock(); loaded = false; value = nil; loads = 0; lock.unlock() }
    }

    private static let shared = Cache()

    /// How many times the asset was loaded in this process. Tests only.
    public static var loadCount: Int { shared.loads }
    public static func resetLoadCountForTesting() { shared.reset() }
}
#endif
