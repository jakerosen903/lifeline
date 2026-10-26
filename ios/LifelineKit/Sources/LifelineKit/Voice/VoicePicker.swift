import Foundation

/// An installed system voice, as the picker sees it. `language` is a BCP 47 code such as "en-US".
public struct VoiceInfo: Equatable, Sendable {
    /// Compact voices are `default`; the larger downloads are `enhanced` and `premium`.
    public enum Quality: Int, Comparable, Sendable {
        case `default`, enhanced, premium
        public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    public var identifier: String
    public var language: String
    public var quality: Quality

    public init(identifier: String, language: String, quality: Quality) {
        self.identifier = identifier; self.language = language; self.quality = quality
    }
}

/// Chooses the voice Lifeline speaks with. The fixed lines are English, so only English voices count.
public enum VoicePicker {
    /// The best en-US voice by quality; with no en-US voice, the best other English one. Ties keep
    /// the installed order.
    public static func best(_ voices: [VoiceInfo]) -> VoiceInfo? {
        let american = voices.filter { language($0) == "en-us" }
        let english = voices.filter { language($0) == "en" || language($0).hasPrefix("en-") }
        return highestQuality(american) ?? highestQuality(english)
    }

    /// True when the voice Lifeline would use is a compact one, or there is none: Settings then
    /// says a better voice can be downloaded.
    public static func onlyCompact(_ voices: [VoiceInfo]) -> Bool {
        (best(voices)?.quality ?? .default) == .default
    }

    /// iOS reports "en-US"; accept "en_US" too.
    private static func language(_ voice: VoiceInfo) -> String {
        voice.language.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    /// The first voice of the highest quality.
    private static func highestQuality(_ voices: [VoiceInfo]) -> VoiceInfo? {
        voices.reduce(nil) { best, voice in
            guard let best, best.quality >= voice.quality else { return voice }
            return best
        }
    }
}
