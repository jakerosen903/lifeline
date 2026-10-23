import Foundation

public struct CrisisLine: Equatable, Sendable {
    public var label: String
    public var number: String
}

/// Pre-written words for the moments the model must never improvise. The disclosure card is a
/// bundled resource; a test asserts it is returned byte for byte. V1 ships en-US only and falls
/// back to it for every other locale.
public enum FixedResponses {
    public enum Error: Swift.Error, Equatable {
        case missing(String)
    }

    public static func disclosure(locale: Locale = .current) throws -> String {
        let candidates = [locale.identifier.replacingOccurrences(of: "_", with: "-"), "en-US"]
        for name in candidates {
            if let url = Bundle.module.url(forResource: "disclosure.\(name)", withExtension: "md", subdirectory: "FixedResponses"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text.hasSuffix("\n") ? String(text.dropLast()) : text
            }
        }
        throw Error.missing("disclosure")
    }

    public static func crisisLine(locale: Locale = .current) -> CrisisLine {
        CrisisLine(label: "Suicide and Crisis Lifeline (US)", number: "988")
    }
}
