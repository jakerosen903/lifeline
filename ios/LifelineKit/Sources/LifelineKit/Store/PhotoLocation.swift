import Foundation

/// Where photo files live: `<root>/Lifeline/photos/<photo id>.jpg`, excluded from the phone's cloud
/// backup like `audio/`. The person's own backup file carries them instead.
public enum PhotoLocation {
    public static let directoryName = "photos"

    /// `<root>/Lifeline/photos`, created and excluded from backup.
    public static func directory(under root: URL) throws -> URL {
        let dir = path(under: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AudioLocation.applyBackupExclusion(to: dir)
        return dir
    }

    /// The same folder, without creating it.
    static func path(under root: URL) -> URL {
        AudioLocation.rootDirectory(under: root).appending(path: directoryName, directoryHint: .isDirectory)
    }
}
