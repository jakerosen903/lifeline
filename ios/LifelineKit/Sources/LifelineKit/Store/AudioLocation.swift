import Foundation

/// Where session audio lives: `<root>/Lifeline/audio/<sessionID>.m4a`, excluded from
/// backup because hours of audio should not surprise an iCloud backup.
public enum AudioLocation {
    /// Default root: the app's Application Support directory.
    public static func defaultRoot(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// Creates the audio directory if needed and marks it excluded from backup.
    public static func directory(under root: URL, fileManager: FileManager = .default) throws -> URL {
        var dir = root.appending(path: "Lifeline/audio", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        return dir
    }

    public static func url(for session: SessionID, under root: URL, fileManager: FileManager = .default) throws -> URL {
        try directory(under: root, fileManager: fileManager).appending(path: fileName(for: session))
    }

    public static func fileName(for session: SessionID) -> String { "\(session.rawValue).m4a" }
}
