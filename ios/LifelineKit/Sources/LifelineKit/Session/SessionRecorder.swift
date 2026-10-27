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
    /// What the interviewer said, in file order. A turn's `endMs` is nil while it plays.
    public var turns: [InterviewerTurn] = []
    /// The turn playing now.
    public var speakingTurn: InterviewerTurnID?
    public var isInterrupted = false
    public var isPaused = false
    public var error: String?
    public init() {}
}

/// What happens around the recorder: a stored segment goes to extraction, every voice event
/// reaches the interviewer, and once the session has ended the caller may let sorting finish in
/// the background. Finishing never waits for it.
public struct RecorderHooks: Sendable {
    public var onSegmentStored: @Sendable (SegmentID) -> Void
    public var onVoiceEvent: @Sendable (VoiceEvent) -> Void
    public var onStopped: @Sendable () -> Void

    public init(onSegmentStored: @escaping @Sendable (SegmentID) -> Void = { _ in },
                onVoiceEvent: @escaping @Sendable (VoiceEvent) -> Void = { _ in },
                onStopped: @escaping @Sendable () -> Void = {}) {
        self.onSegmentStored = onSegmentStored
        self.onVoiceEvent = onVoiceEvent
        self.onStopped = onStopped
    }
}

/// A turn the interviewer wants spoken. The recorder gives it an id and stores it once it starts.
public struct TurnDraft: Hashable, Sendable {
    public var kind: TurnKind
    public var source: TurnSource
    public var text: String
    public init(kind: TurnKind, source: TurnSource, text: String) {
        self.kind = kind; self.source = source; self.text = text
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
    private let turns: InterviewerTurnRepository
    private let audioURL: @Sendable (SessionID) throws -> URL
    private let now: @Sendable () -> Date
    private let hooks: RecorderHooks
    private var session: Session?
    private var eventTask: Task<Void, Never>?
    /// Turns handed to the voice that have not started yet. A dropped turn never starts, so it gets no row.
    private var drafts: [InterviewerTurnID: TurnDraft] = [:]

    public init(voice: any VoiceSession, sessions: SessionRepository, turns: InterviewerTurnRepository,
                audioURL: @escaping @Sendable (SessionID) throws -> URL,
                now: @escaping @Sendable () -> Date = Date.init,
                hooks: RecorderHooks = RecorderHooks()) {
        self.voice = voice
        self.sessions = sessions
        self.turns = turns
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
        try sessions.markEnded(row.id, at: row.endedAt!)   // one column: a stage log written meanwhile stands
        session = row
        hooks.onStopped()
    }

    /// The arc's stage log, written whenever it changes so a crash keeps the story of the session.
    public func record(stageLog: String) throws {
        guard var row = session else { return }
        row.stageLog = stageLog
        try sessions.updateStageLog(row.id, stageLog)
        session = row
    }

    public func pause() async throws {
        guard let row = session, row.endedAt == nil else { return }
        try await voice.pause()
    }

    public func resume() async throws {
        guard let row = session, row.endedAt == nil else { return }
        try await voice.resume()
    }

    /// Cuts the turn that is playing, if any: the person asked for quiet. The voice reports its end, interrupted.
    public func interruptTurn() async {
        guard let row = session, row.endedAt == nil else { return }
        await voice.interrupt()
    }

    /// Hands the turn to the voice. Its row is written when the voice reports that it started,
    /// so a turn dropped while paused leaves no row, and a crash mid-turn leaves one with no end.
    /// Returns false when the session has ended or the voice refused the turn.
    @discardableResult
    public func speak(_ draft: TurnDraft) async -> Bool {
        guard let row = session, row.endedAt == nil else { return false }
        let id = InterviewerTurnID()
        drafts[id] = draft
        let accepted = await voice.say(SpokenTurn(id: id, text: draft.text))
        if !accepted { drafts[id] = nil }
        return accepted
    }

    /// After a crash: every session left open has its recording ended. One with words waits for
    /// its landing (the app opens it first); one with nothing said is closed quietly.
    /// Returns the sessions to resume, newest first.
    public nonisolated static func recoverUnfinishedSessions(_ repo: SessionRepository, now: Date = .now) throws -> [Session] {
        var resume: [Session] = []
        for s in try repo.unfinishedSessions() {
            try repo.markEnded(s.id, at: now)
            try repo.appendToStageLog(s.id, reason: "crash", at: now)
            if try repo.segments(in: s.id).isEmpty {
                try repo.markLanded(s.id, now: now)
            } else if let updated = try repo.fetch(s.id) {
                resume.append(updated)
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
        case .turnStarted(let id, let startMs):
            storeTurn(id, startMs: startMs)
        case .turnEnded(let id, let endMs, let interrupted):
            endTurn(id, endMs: endMs, interrupted: interrupted)
        case .heard:
            break   // the interviewer loop acts on commands; the recorder stores nothing for them
        }
        hooks.onVoiceEvent(event)
    }

    private func storeTurn(_ id: InterviewerTurnID, startMs: Milliseconds) {
        guard let session, let draft = drafts.removeValue(forKey: id) else { return }
        let turn = InterviewerTurn(id: id, sessionID: session.id, kind: draft.kind, source: draft.source, text: draft.text,
                                   startMs: startMs, endMs: nil, interrupted: false)
        do {
            try turns.insert(turn)
            state.turns.append(turn)
            state.speakingTurn = id
        } catch {
            state.error = "could not save a turn: \(error)"
        }
    }

    /// A turn cut before it started has no row: its end is ignored.
    private func endTurn(_ id: InterviewerTurnID, endMs: Milliseconds, interrupted: Bool) {
        drafts[id] = nil
        guard let index = state.turns.firstIndex(where: { $0.id == id }) else { return }
        do {
            try turns.end(id, atMs: endMs, interrupted: interrupted)
            state.turns[index].endMs = endMs
            state.turns[index].interrupted = interrupted
        } catch {
            state.error = "could not end a turn: \(error)"
        }
        if state.speakingTurn == id { state.speakingTurn = nil }
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
