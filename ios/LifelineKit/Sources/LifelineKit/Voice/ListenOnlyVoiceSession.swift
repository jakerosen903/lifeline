import Foundation

/// The V1 voice session: it listens and never speaks. One actor owns the file clock and
/// feeds every chunk to the sink, the transcriber and the segmenter, in that order.
public actor ListenOnlyVoiceSession: VoiceSession {
    public struct Timing: Sendable {
        /// After asking the transcriber to finalize, close the segment once this long passes with no new final.
        public var finalizeGraceMs: Int
        /// Never wait longer than this for finals.
        public var finalizeTimeoutMs: Int
        public init(finalizeGraceMs: Int = 400, finalizeTimeoutMs: Int = 2_000) {
            self.finalizeGraceMs = finalizeGraceMs; self.finalizeTimeoutMs = finalizeTimeoutMs
        }
    }

    private let source: any AudioSource
    private let sink: any AudioSink
    private let transcriber: any Transcriber
    private let timing: Timing
    private let log: @Sendable (String) -> Void

    private var segmenter: Segmenter
    private var pendingWords: [TranscribedWord] = []
    private var lastChunkEndMs: Milliseconds = 0
    private var events: AsyncStream<VoiceEvent>.Continuation?
    private var sourceTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var closeWaiter: (segmentEndMs: Milliseconds, deadline: ContinuousClock.Instant, continuation: CheckedContinuation<Void, Never>)?
    private var graceTimer: Task<Void, Never>?

    public init(source: any AudioSource, sink: any AudioSink, transcriber: any Transcriber,
                segmenter: SegmenterConfig = .init(), timing: Timing = .init(),
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.source = source
        self.sink = sink
        self.transcriber = transcriber
        self.segmenter = Segmenter(config: segmenter)
        self.timing = timing
        self.log = log
    }

    // MARK: VoiceSession

    public func start(writingTo audioURL: URL) async throws -> AsyncStream<VoiceEvent> {
        let (stream, continuation) = AsyncStream<VoiceEvent>.makeStream()
        events = continuation
        try await sink.open(url: audioURL, format: source.format)
        let results = try await transcriber.start(format: source.format)
        let chunks = try await source.start()
        resultsTask = Task { [weak self] in
            for await result in results { await self?.handle(result) }
        }
        sourceTask = Task { [weak self] in
            for await event in chunks { await self?.handle(event) }
        }
        return stream
    }

    public func stop() async throws {
        await source.stop()
        await sourceTask?.value
        await closeSegments(segmenter.flush(atMs: lastChunkEndMs))
        await transcriber.finish()
        await resultsTask?.value
        try await sink.close()
        events?.finish()
        events = nil
    }

    public func say(_ text: String) async { log("say (no-op in listen-only): \(text)") }
    public func acknowledge() async { log("acknowledge (no-op in listen-only)") }
    public func interrupt() async { log("interrupt (no-op in listen-only)") }

    // MARK: Source events

    private func handle(_ event: AudioSourceEvent) async {
        switch event {
        case .chunk(let chunk):
            do { try await sink.write(chunk) } catch { emit(.failed("audio write: \(error)")) }
            await transcriber.feed(chunk)
            lastChunkEndMs = max(lastChunkEndMs, chunk.range.end)
            await closeSegments(segmenter.observe(levelDb: chunk.levelDb, startMs: chunk.startMs, durationMs: chunk.durationMs))
        case .interrupted:
            await closeSegments(segmenter.flush(atMs: lastChunkEndMs))
            emit(.interrupted)
        case .resumed:
            emit(.resumed)
        }
    }

    private func closeSegments(_ segmenterEvents: [SegmenterEvent]) async {
        for event in segmenterEvents {
            switch event {
            case .speechStarted(let ms):
                emit(.speechStarted(atMs: ms))
            case .pauseObserved(let ms):
                log("pause \(ms)")
            case .segmentEnded(let range):
                emit(.userPaused(afterMs: range.end))
                await transcriber.finalize(throughMs: range.end)
                await waitForFinals(throughMs: range.end)
                emit(.segmentClosed(takeSegment(range)))
            }
        }
    }

    /// Every unclaimed word that starts before the segment's end belongs to it. Words that
    /// start later are held for the next segment. Earlier stragglers (from an abandoned blip)
    /// are kept rather than lost.
    private func takeSegment(_ range: MsRange) -> SegmentTranscript {
        let (inside, held) = pendingWords.stablePartition { $0.range.start < range.end }
        pendingWords = held
        return SegmentTranscript(range: range, text: inside.map(\.text).joined(separator: " "), words: inside)
    }

    // MARK: Transcriber results

    private func handle(_ result: TranscriptResult) {
        guard result.isFinal else {
            emit(.transcriptPartial(result.text))
            return
        }
        pendingWords.append(contentsOf: result.words)
        emit(.transcriptFinal(result))
        if let waiter = closeWaiter {
            if result.range.end >= waiter.segmentEndMs {
                resumeCloseWaiter()
            } else {
                restartGraceTimer()
            }
        }
    }

    private func waitForFinals(throughMs: Milliseconds) async {
        if pendingWords.contains(where: { $0.range.end >= throughMs }) { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            closeWaiter = (throughMs, .now + .milliseconds(timing.finalizeTimeoutMs), continuation)
            restartGraceTimer()
        }
    }

    private func restartGraceTimer() {
        graceTimer?.cancel()
        guard let waiter = closeWaiter else { return }
        let wait = min(.milliseconds(timing.finalizeGraceMs), waiter.deadline - .now)
        graceTimer = Task { [weak self] in
            try? await Task.sleep(for: max(wait, .zero))
            guard !Task.isCancelled else { return }
            await self?.resumeCloseWaiter()
        }
    }

    private func resumeCloseWaiter() {
        graceTimer?.cancel()
        graceTimer = nil
        closeWaiter?.continuation.resume()
        closeWaiter = nil
    }

    private func emit(_ event: VoiceEvent) {
        events?.yield(event)
    }
}

private extension Array {
    /// Splits into (matching, rest), both in original order.
    func stablePartition(_ belongs: (Element) -> Bool) -> ([Element], [Element]) {
        var yes: [Element] = [], no: [Element] = []
        for e in self { if belongs(e) { yes.append(e) } else { no.append(e) } }
        return (yes, no)
    }
}
