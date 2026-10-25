import Foundation

/// An idea's title is the person's own words (M7): a run of at most 8 words copied from the
/// segment, or a dated default. The model never composes one.
public enum IdeaTitle {
    public static let maxWords = 8

    /// The title when it is a contiguous run of the segment's words (case and edge punctuation
    /// folded) of at most 8 words; nil otherwise.
    public static func verbatim(_ title: String?, in segmentText: String) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let words = OutputValidator.tokens(title)
        guard !words.isEmpty, words.count <= maxWords, OutputValidator.contains(segmentText, title) else { return nil }
        return title
    }

    /// "An idea you mentioned on 25 October".
    public static func defaultTitle(toldOn date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM"
        return "An idea you mentioned on \(formatter.string(from: date))"
    }

    /// What the card and the page show.
    public static func title(proposed: String?, segmentText: String, toldOn date: Date, calendar: Calendar = .current) -> String {
        verbatim(proposed, in: segmentText) ?? defaultTitle(toldOn: date, calendar: calendar)
    }
}
