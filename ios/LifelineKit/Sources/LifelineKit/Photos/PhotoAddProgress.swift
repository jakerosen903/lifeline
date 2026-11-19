/// The two lines a page shows when photos are added from the picker (part 4). One photo keeps the lines it had
/// before a pick could hold more than one.
public enum PhotoAddProgress {
    /// The line while photo `index` (from 1) of `count` is added.
    public static func line(adding index: Int, of count: Int) -> String {
        count <= 1 ? "Adding the photo…" : "Adding photo \(index) of \(count)…"
    }

    /// The one line at the end of a pick: nil when every photo was added. One failure says why; more say how many.
    public static func failureLine(failed: Int, lastError: String) -> String? {
        switch failed {
        case ..<1: nil
        case 1: "Could not add this photo: \(lastError)"
        default: "\(failed) photos could not be added."
        }
    }
}
