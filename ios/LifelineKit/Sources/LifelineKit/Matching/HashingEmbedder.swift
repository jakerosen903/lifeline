import Foundation

/// A bag-of-words embedding: each word hashes to one of a fixed number of dimensions, so cosine
/// measures word overlap. Deterministic, dependency-free, the same on every platform. Used under
/// UI testing and as the fallback when the device has no sentence-embedding asset.
public struct HashingEmbedder: SentenceEmbedder {
    public static let dimensions = 256
    public let model = "hash-256"

    public init() {}

    public func vector(for text: String) -> [Float]? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        var out = [Float](repeating: 0, count: Self.dimensions)
        for word in words { out[Int(Self.fnv1a(word) % UInt64(Self.dimensions))] += 1 }
        return out
    }

    /// FNV-1a, so the hash is stable across launches (Swift's `hashValue` is seeded per process).
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        return hash
    }
}
