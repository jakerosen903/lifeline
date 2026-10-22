import CoreMedia
import Foundation
import Speech

/// Turns a transcriber's attributed text into words with millisecond spans.
///
/// Rules: one word per timed run; a timed run holding several whitespace-separated tokens is
/// split evenly across its range; untimed text (punctuation) is glued to the previous word;
/// untimed text before the first word, and whitespace-only runs, are dropped.
public enum WordRuns {
    public static func words(from text: AttributedString) -> [TranscribedWord] {
        var words: [TranscribedWord] = []
        for run in text.runs {
            let runText = String(text[run.range].characters)
            let tokens = runText.split(whereSeparator: \.isWhitespace).map(String.init)
            if let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] {
                words.append(contentsOf: split(tokens, across: range))
            } else if !tokens.isEmpty, !words.isEmpty {
                words[words.count - 1].text += tokens.joined()
            }
        }
        return words
    }

    private static func split(_ tokens: [String], across range: CMTimeRange) -> [TranscribedWord] {
        guard !tokens.isEmpty else { return [] }
        let start = milliseconds(range.start), end = milliseconds(range.end)
        let step = Double(end - start) / Double(tokens.count)
        return tokens.enumerated().map { i, token in
            let a = start + Int((step * Double(i)).rounded())
            let b = i == tokens.count - 1 ? end : start + Int((step * Double(i + 1)).rounded())
            return TranscribedWord(text: token, range: MsRange(start: a, end: b))
        }
    }

    /// Rounded milliseconds; 0 for an invalid or indefinite time.
    public static func milliseconds(_ time: CMTime) -> Milliseconds {
        guard time.isNumeric else { return 0 }
        return Int((time.seconds * 1_000).rounded())
    }
}
