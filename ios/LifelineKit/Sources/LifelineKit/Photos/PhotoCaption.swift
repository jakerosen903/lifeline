import Foundation

/// The words the app says about a photo. It says what the person did and what the file said; never what is in the picture.
public enum PhotoCaption {
    /// "taken 14 June 2012": the camera's date only (decision 6). Nil when the file had none.
    public static func taken(_ takenAt: PhotoTakenAt?) -> String? {
        guard let date = takenAt?.date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        // A civil date has no time zone: build it at noon in UTC and format it in UTC, so no zone moves the day.
        guard let noon = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return "taken \(formatter.string(from: noon))"
    }

    /// The accessibility label: where the person put the photo.
    public static func label(title: String, isOwner: Bool, isMemory: Bool) -> String {
        if isMemory { return "Photo for \(title)" }
        return isOwner ? "Photo of you" : "Photo of \(title)"
    }
}
