import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage

/// Apple's on-device English embeddings. No network, no key. The classic sentence embedding
/// first; when a device does not have it, the contextual embedding (iOS 17+), whose token
/// vectors are mean-pooled; when neither has its assets yet, nil, and the assets are requested
/// once so a later launch has them. The model is loaded once per process and every call is
/// serialised: loading per sentence would make a backfill of N memories N asset loads, and
/// `vector(for:)` is not documented thread-safe.
public struct NLSentenceEmbedder: SentenceEmbedder {
    public init() {}

    /// Names the model actually in use, so vectors from different models are never compared.
    public var model: String { Self.shared.model() }

    /// Only the classic sentence model is calibrated for the 0.80 card threshold. Mean-pooled
    /// contextual vectors score 0.78–0.95 for unrelated pairs on sample text, so they rank for
    /// the packet and leave the card line to the extractor.
    public var suggestsOnItsOwn: Bool { model == "nl-sentence-en" }

    public func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Self.shared.vector(for: trimmed)
    }

    /// One line for the launch log: which model this device has, if any.
    public static var availability: String { shared.describe() }

    // MARK: - One load per process

    private enum Backend {
        case sentence(NLEmbedding)
        case contextual(NLContextualEmbedding)
        case none
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded = false
        private var backend: Backend = .none
        private(set) var loads = 0

        private func loadIfNeeded() {
            guard !loaded else { return }
            loaded = true
            loads += 1
            if let sentence = NLEmbedding.sentenceEmbedding(for: .english) {
                backend = .sentence(sentence)
                return
            }
            if let contextual = NLContextualEmbedding(language: .english) {
                if contextual.hasAvailableAssets, (try? contextual.load()) != nil {
                    backend = .contextual(contextual)
                    return
                }
                // Not here yet: ask once; the next launch finds them.
                contextual.requestAssets { _, _ in }
            }
            backend = .none
        }

        func model() -> String {
            lock.lock(); defer { lock.unlock() }
            loadIfNeeded()
            switch backend {
            case .sentence: return "nl-sentence-en"
            case .contextual: return "nl-contextual-en"
            case .none: return "nl-none"
            }
        }

        func vector(for text: String) -> [Float]? {
            lock.lock(); defer { lock.unlock() }
            loadIfNeeded()
            switch backend {
            case .sentence(let embedding):
                return embedding.vector(for: text)?.map { Float($0) }
            case .contextual(let embedding):
                guard let result = try? embedding.embeddingResult(for: text, language: .english) else { return nil }
                var sum = [Float](repeating: 0, count: embedding.dimension)
                var count: Float = 0
                result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                    for i in vector.indices where i < sum.count { sum[i] += Float(vector[i]) }
                    count += 1
                    return true
                }
                guard count > 0 else { return nil }
                return sum.map { $0 / count }
            case .none:
                return nil
            }
        }

        func describe() -> String {
            lock.lock(); defer { lock.unlock() }
            loadIfNeeded()
            switch backend {
            case .sentence(let e): return "sentence embedding, \(e.dimension) dims"
            case .contextual(let e): return "contextual embedding, \(e.dimension) dims"
            case .none: return "no embedding assets on this device (requested)"
            }
        }

        func reset() { lock.lock(); loaded = false; backend = .none; loads = 0; lock.unlock() }
    }

    private static let shared = Cache()

    /// How many times the assets were loaded in this process. Tests only.
    public static var loadCount: Int { shared.loads }
    public static func resetLoadCountForTesting() { shared.reset() }
}
#endif
