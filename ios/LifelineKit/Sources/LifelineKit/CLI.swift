import Foundation

/// The `lifeline` command's logic, kept in the package so tests can call it.
/// Commands: `sessions --db <path>`, `import <transcript.json> --db <path>`,
/// `extract --session <id> --db <path> [--version v1] [--model <id>]`.
public enum CLI {
    public struct Result: Equatable {
        public let exitCode: Int32
        public let output: String
    }

    public static let usage = """
    usage:
      lifeline sessions --db <path>                        list sessions (id, started_at, segment count)
      lifeline import <transcript.json> --db <path>        load a transcript as a session
      lifeline extract --session <id> --db <path> [--version v1] [--model <id>]
                                                           run the extractor over the session's pending segments
                                                           (reads ANTHROPIC_API_KEY from the environment)
      lifeline resolve --all --db <path>                   re-run the resolver over every memory and print what changed

    """

    public static func run(_ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
                           service: (any ExtractionService)? = nil) async throws -> Result {
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
        case "resolve":
            guard args == ["--all"] else { return Result(exitCode: 2, output: usage) }
            let store = ExtractionStore(try AppDatabase.open(at: URL(fileURLWithPath: dbPath)))
            let report = try ResolverRunner(store: store).run()
            var lines = report.changes.map { "\($0.title)\t\($0.before.displayText)\t→\t\($0.after.displayText)" }
            lines.append("\(report.placed) placed, \(report.floatingCreated) floating created, \(report.curiosityOpen) questions open")
            return Result(exitCode: 0, output: lines.joined(separator: "\n") + "\n")
        case "extract":
            guard let sessionArg = takeOption("--session", from: &args) else { return Result(exitCode: 2, output: usage) }
            var config = ExtractorConfig.default
            if let version = takeOption("--version", from: &args) { config.version = version }
            if let model = takeOption("--model", from: &args) { config.model = model }
            guard args.isEmpty else { return Result(exitCode: 2, output: usage) }
            return try await extract(session: SessionID(rawValue: sessionArg), dbPath: dbPath, config: config,
                                     environment: environment, service: service)
        default:
            return Result(exitCode: 2, output: usage)
        }
    }

    private static func extract(session: SessionID, dbPath: String, config: ExtractorConfig, environment: [String: String],
                                service given: (any ExtractionService)?) async throws -> Result {
        let store = ExtractionStore(try AppDatabase.open(at: URL(fileURLWithPath: dbPath)))
        guard try store.sessions.fetch(session) != nil else { return Result(exitCode: 2, output: "no session \(session.rawValue)\n") }
        let service: any ExtractionService
        if let given {
            service = given
        } else {
            guard let key = environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
                return Result(exitCode: 3, output: "ANTHROPIC_API_KEY is not set\n")
            }
            service = AnthropicExtractionService(config: config, apiKey: { key })
        }

        let segments = try store.sessions.segments(in: session)
        let queue = ExtractionQueue(session: session, service: service, store: store, log: { FileHandle.standardError.write(Data("[extract] \($0)\n".utf8)) })
        for segment in segments where segment.status == .pending { await queue.enqueue(segment.id) }
        await queue.drain()

        var lines: [String] = []
        var total = 0, rejected = 0
        for segment in segments {
            for c in try store.candidates.candidates(for: segment.id) where c.extractorVersion == service.version {
                total += 1
                if c.rejection != nil { rejected += 1 }
                lines.append([String(segment.index), c.kind.rawValue, c.status.rawValue, String(format: "%.2f", c.confidence),
                              label(c), c.rejection ?? ""].joined(separator: "\t").trimmingCharacters(in: CharacterSet(charactersIn: "\t")))
            }
        }
        let failed = try store.sessions.segments(in: session, status: .pending).count
        lines.append("\(total) candidates, \(rejected) rejected, \(failed) failed segments")
        return Result(exitCode: 0, output: lines.joined(separator: "\n") + "\n")
    }

    private static func label(_ candidate: Candidate) -> String {
        if let m = CandidatePayload.memory(candidate) { return m.title }
        if let m = CandidatePayload.mention(candidate) { return m.text }
        return candidate.payload
    }

    /// Removes `--name value` from `args` and returns the value.
    private static func takeOption(_ name: String, from args: inout [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        let value = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return value
    }
}
