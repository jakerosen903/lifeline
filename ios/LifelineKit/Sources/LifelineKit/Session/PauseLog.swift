import Foundation

/// Appends observed pause lengths to a text file for calibrating the later end-of-thought model.
/// One line per pause: ISO-8601 time, a tab, the pause in milliseconds.
public actor PauseLog {
    private let url: URL
    private static let prefix = "pause "

    public init(url: URL) {
        self.url = url
    }

    /// Accepts any voice-session log line and keeps only "pause <ms>" lines.
    public func record(_ line: String) {
        guard line.hasPrefix(Self.prefix) else { return }
        let ms = line.dropFirst(Self.prefix.count)
        let entry = "\(Date.now.ISO8601Format())\t\(ms)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
