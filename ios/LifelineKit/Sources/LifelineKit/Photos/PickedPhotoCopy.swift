import Foundation

/// The app's own copy of a picked photo, in the temporary folder, while the library makes its downscaled copy.
/// It is the full-resolution original, with its EXIF and GPS. The import removes it when done; a kill during the
/// import leaves it, so launch removes every one left behind. The name prefix lives only here.
public enum PickedPhotoCopy {
    public static let prefix = "picked-"

    /// A fresh name in `folder` that keeps the picked file's extension (none when it has none).
    public static func url(in folder: URL, extension ext: String) -> URL {
        folder.appending(path: prefix + UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
    }

    /// Removes every picked copy in `folder`. A folder that cannot be read, or a file that will not go, is skipped:
    /// the system clears the temporary folder in time. Returns how many went.
    @discardableResult
    public static func removeLeftovers(in folder: URL = FileManager.default.temporaryDirectory) -> Int {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        var removed = 0
        for name in names where name.hasPrefix(prefix) {
            if (try? fm.removeItem(at: folder.appending(path: name))) != nil { removed += 1 }
        }
        return removed
    }
}
