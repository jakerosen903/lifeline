import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage

/// Apple's on-device English sentence embedding. No network, no key. Nil when the asset is
/// not available on this device or platform.
public struct NLSentenceEmbedder: SentenceEmbedder {
    public let model = "nl-sentence-en"

    public init() {}

    public func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = embedding.vector(for: trimmed) else { return nil }
        return vector.map { Float($0) }
    }
}
#endif
