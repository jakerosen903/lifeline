public struct EchoConfig: Equatable, Sendable {
    /// Widens each playback window on both sides, for transcriber timing drift.
    public var padMs: Milliseconds
    /// Share of the played part of a turn that the heard words must match.
    public var matchShare: Double
    /// Partial words outside the turn that count as the person talking over the app.
    public var bargeInWords: Int

    public init(padMs: Milliseconds = 300, matchShare: Double = 0.6, bargeInWords: Int = 2) {
        self.padMs = padMs
        self.matchShare = matchShare
        self.bargeInWords = bargeInWords
    }
}

/// The span of recording time in which the app spoke one turn, and the turn's text.
public struct PlaybackWindow: Equatable, Sendable {
    public var range: MsRange
    public var text: String

    public init(range: MsRange, text: String) {
        self.range = range
        self.text = text
    }
}

/// Tells the app's own spoken words from the person's, by aligning heard words to the turn text.
public enum EchoFilter {
    /// `words` without the ones that echo a turn the app spoke in `windows`.
    public static func personsWords(
        _ words: [TranscribedWord], windows: [PlaybackWindow], config: EchoConfig
    ) -> [TranscribedWord] {
        var remaining = words
        for window in windows {
            remaining = removingEcho(of: window, from: remaining, config: config)
        }
        return remaining
    }

    /// How many tokens of `partial` fall outside the in-order match with `turnText`.
    public static func nonMatchingCount(_ partial: String, turnText: String) -> Int {
        let heard = TurnText.tokens(partial)
        return heard.count - alignment(heard, to: TurnText.tokens(turnText)).count
    }

    private static func removingEcho(
        of window: PlaybackWindow, from words: [TranscribedWord], config: EchoConfig
    ) -> [TranscribedWord] {
        let low = window.range.start - config.padMs
        let high = window.range.end + config.padMs
        let turn = TurnText.tokens(window.text)

        // Flatten the in-window words to tokens, remembering which word each came from.
        var heard: [String] = []
        var owner: [Int] = []
        for (index, word) in words.enumerated() where word.range.start >= low && word.range.start <= high {
            for token in TurnText.tokens(word.text) {
                heard.append(token)
                owner.append(index)
            }
        }

        let pairs = alignment(heard, to: turn)
        guard pairs.count >= 2, let last = pairs.last?.turn,
              Double(pairs.count) / Double(last + 1) >= config.matchShare
        else { return words }

        let echoed = Set(pairs.map { owner[$0.heard] })
        return words.enumerated().filter { !echoed.contains($0.offset) }.map(\.element)
    }

    /// A longest common subsequence of `heard` and `turn`, as index pairs in increasing order.
    private static func alignment(_ heard: [String], to turn: [String]) -> [(heard: Int, turn: Int)] {
        guard !heard.isEmpty, !turn.isEmpty else { return [] }
        // length[i][j]: LCS length of heard[i...] and turn[j...].
        var length = Array(repeating: Array(repeating: 0, count: turn.count + 1), count: heard.count + 1)
        for i in stride(from: heard.count - 1, through: 0, by: -1) {
            for j in stride(from: turn.count - 1, through: 0, by: -1) {
                length[i][j] = heard[i] == turn[j]
                    ? length[i + 1][j + 1] + 1
                    : max(length[i + 1][j], length[i][j + 1])
            }
        }
        var pairs: [(heard: Int, turn: Int)] = []
        var i = 0, j = 0
        while i < heard.count, j < turn.count {
            if heard[i] == turn[j] {
                pairs.append((i, j))
                i += 1; j += 1
            } else if length[i + 1][j] >= length[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
