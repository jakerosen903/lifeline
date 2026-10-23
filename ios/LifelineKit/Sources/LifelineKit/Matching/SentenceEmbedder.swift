import Foundation

/// Turns a sentence into a vector, on device. Nil when the model cannot embed the text (asset
/// missing, unsupported language): every caller must work with no vectors at all.
public protocol SentenceEmbedder: Sendable {
    /// Names the model, so vectors from different models are never compared.
    var model: String { get }
    func vector(for text: String) -> [Float]?
    /// False for a model whose scores sit high for every pair (mean-pooled token vectors):
    /// it still ranks memories for the packet, but a score alone never puts "Same as X?" on
    /// a card; the extractor decides. True once a model's threshold is calibrated.
    var suggestsOnItsOwn: Bool { get }
}

public extension SentenceEmbedder {
    var suggestsOnItsOwn: Bool { true }
}
