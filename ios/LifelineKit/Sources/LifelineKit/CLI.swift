import Foundation

/// The `lifeline` command's logic, kept in the package so tests can call it.
/// Commands: `sessions --db <path>`, `import <transcript.json> --db <path>`.
public enum CLI {
    public struct Result: Equatable {
        public let exitCode: Int32
        public let output: String
    }

    public static let usage = """
    usage:
      lifeline sessions --db <path>              list sessions (id, started_at, segment count)
      lifeline import <transcript.json> --db <path>   load a transcript as a session

    """

    public static func run(_ arguments: [String]) throws -> Result {
        var args = arguments
        guard !args.isEmpty else { return Result(exitCode: 2, output: usage) }
        let command = args.removeFirst()
        guard let dbPath = takeOption("--db", from: &args) else { return Result(exitCode: 2, output: usage) }

        switch command {
        case "sessions":
            let repo = SessionRepository(try AppDatabase.open(at: URL(fileURLWithPath: dbPath)))
            let lines = try repo.listSessions().map { s in
                "\(s.id.rawValue)\t\(s.startedAt.ISO8601Format())\t\(try repo.segments(in: s.id).count) segments"
            }
            return Result(exitCode: 0, output: lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
        case "import":
            guard args.count == 1 else { return Result(exitCode: 2, output: usage) }
            let repo = SessionRepository(try AppDatabase.open(at: URL(fileURLWithPath: dbPath)))
            let id = try TranscriptImport.importTranscript(at: URL(fileURLWithPath: args[0]), into: repo)
            return Result(exitCode: 0, output: id.rawValue + "\n")
        default:
            return Result(exitCode: 2, output: usage)
        }
    }

    /// Removes `--name value` from `args` and returns the value.
    private static func takeOption(_ name: String, from args: inout [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        let value = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return value
    }
}
