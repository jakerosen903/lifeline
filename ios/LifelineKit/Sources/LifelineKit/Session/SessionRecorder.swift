import Foundation

/// What a session screen shows. Published on `states` after every change.
public struct RecorderState: Equatable, Sendable {
    public var sessionID: SessionID?
    public var startedAt: Date?
    /// The utterance in progress, revised as the transcriber listens.
    public var partial: String = ""
    /// Final text since the last closed segment. Shown so words do not vanish between finals.
    public var spoken: String = ""
    /// True from speech start to the pause that ends it; drives the listening indicator.
    public var isSpeaking = false
    public var segments: [Segment] = []
    public var isInterrupted = false
    public var isPaused = false
    public var error: String?
    public init() {}
}

/// What happens around the recorder: a stored segment goes to extraction, and once the session
/// has ended the caller may let sorting finish in the background. Finishing never waits for it.
public struct RecorderHooks: Sendable {
    public var onSegmentStored: @Sendable (SegmentID) -> Void
    public var onStopped: @Sendable () -> Void

    public init(onSegmentStored: @escaping @Sendable (SegmentID) -> Void = { _ in },
                onStopped: @escaping @Sendable () -> Void = {}) {
        self.onSegmentStored = onSegmentStored
        self.onStopped = onStopped
    }
}

/// Turns voice events into database rows. The session row is written before capture starts,
/// so a crash leaves a session with `endedAt == nil` that the next launch can recover.
public actor SessionRecorder {
    public private(set) var state = RecorderState() {
        didSet { stateContinuation.yield(state) }
    }
    public nonisolated let states: AsyncStream<RecorderState>
    private let stateContinuation: AsyncStream<RecorderState>.Continuation

    private let voice: any VoiceSession
    private let sessions: SessionRepository
    private let audioURL: @Sendable (SessionID) throws -> URL
    private let now: @Sendable () -> Date
    private let hooks: RecorderHooks
    private var session: Session?
    private var eventTask: Task<Void, Never>?

    public init(voice: any VoiceSession, sessions: SessionRepository,
                audioURL: @escaping @Sendable (SessionID) throws -> URL,
                now: @escaping @Sendable () -> Date = Date.init,
                hooks: RecorderHooks = RecorderHooks()) {
        self.voice = voice
        self.sessions = sessions
        self.audioURL = audioURL
        self.now = now
        self.hooks = hooks
        (states, stateContinuation) = AsyncStream.makeStream()
    }

    /// Inserts the session row, then starts capture. If capture fails to start, the row is removed.
    /// The caller may choose the id so collaborators (the extraction queue) can be built first.
    @discardableResult
    public func start(id: SessionID = SessionID(), kind: SessionKind = .quick) async throws -> SessionID {
        precondition(session == nil, "SessionRecorder is single-use")
        let url = try audioURL(id)
        let row = Session(id: id, startedAt: now(), endedAt: nil, audioPath: url.lastPathComponent,
                          stageLog: "[]", landingChoiceMade: false, kind: kind)
        try sessions.insert(row)
        session = row
        state.sessionID = id
        state.startedAt = row.startedAt

        let events: AsyncStream<VoiceEvent>
        do {
            events = try await voice.start(writingTo: url)
        } catch {
            try? sessions.delete(id)
            session = nil
            throw error
        }
        eventTask = Task { [weak self] in
            for await event in events { await self?.handle(event) }
        }
        return id
    }

    /// Stops capture, stores the closing words and marks the session ended. It returns as soon as
    /// that is done: sorting what was said is the caller's background work. Safe to call twice.
    public func stop() async throws {
        guard var row = session, row.endedAt == nil else { return }
        try await voice.stop()
        await eventTask?.value
        row.endedAt = now()
        try sessions.update(row)
        session = row
        hooks.onStopped()
    }

    public func pause() async throws {
        guard let row = session, row.endedAt == nil else { return }
        try await voice.pause()
    }

    public func resume() async throws {
        guard let row = session, row.endedAt == nil else { return }
        try await voice.resume()
    }

    /// After a crash: every session left open has its recording ended. One with words waits for
    /// its landing (the app opens it first); one with nothing said is closed quietly.
    /// Returns the sessions to resume, newest first.
    public nonisolated static func recoverUnfinishedSessions(_ repo: SessionRepository, now: Date = .now) throws -> [Session] {
        var resume: [Session] = []
        for var s in try repo.unfinishedSessions() {
            s.endedAt = now
            try repo.update(s)
            if try repo.segments(in: s.id).isEmpty {
                try repo.markLanded(s.id, stageLog: s.stageLog)
            } else {
                resume.append(s)
            }
        }
        return resume.sorted { $0.startedAt > $1.startedAt }
    }

    private func handle(_ event: VoiceEvent) {
        switch event {
        case .speechStarted:
            state.isSpeaking = true
        case .transcriptPartial(let text):
            state.partial = text
        case .transcriptFinal(let result):
            state.spoken = [state.spoken, result.text].filter { !$0.isEmpty }.joined(separator: " ")
            state.partial = ""
        case .userPaused:
            state.isSpeaking = false
        case .segmentClosed(let transcript):
            store(transcript)
            state.partial = ""
            state.spoken = ""
        case .interrupted:
            state.isInterrupted = true
        case .paused:
            state.isPaused = true
            state.isSpeaking = false
        case .resumed:
            state.isInterrupted = false
            state.isPaused = false
        case .failed(let message):
            state.error = message
        }
    }

    /// A segment with no words (noise, music) is not worth a row.
    private func store(_ transcript: SegmentTranscript) {
        guard let session, !transcript.words.isEmpty else { return }
        let segment = Segment(id: .init(), sessionID: session.id, index: state.segments.count,
                              startMs: transcript.range.start, endMs: transcript.range.end,
                              text: transcript.text, status: .pending)
        let words = transcript.words.enumerated().map { i, w in
            Word(segmentID: segment.id, index: i, text: w.text, startMs: w.range.start, endMs: w.range.end)
        }
        do {
            try sessions.insert(segment, words: words)
            state.segments.append(segment)
            hooks.onSegmentStored(segment.id)
        } catch {
            state.error = "could not save segment \(segment.index): \(error)"
        }
    }
}
