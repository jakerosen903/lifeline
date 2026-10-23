import Foundation

/// Turns a sentence into a vector, on device. Nil when the model cannot embed the text (asset
/// missing, unsupported language): every caller must work with no vectors at all.
public protocol SentenceEmbedder: Sendable {
    /// Names the model, so vectors from different models are never compared.
    var model: String { get }
    func vector(for text: String) -> [Float]?
}
