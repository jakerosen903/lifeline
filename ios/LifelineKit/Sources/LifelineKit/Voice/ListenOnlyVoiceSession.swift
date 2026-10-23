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
    private var closeWaiter: (segmentEndMs: Milliseconds, deadline: ContinuousClock.Instant, generation: Int, continuation: CheckedContinuation<Void, Never>)?
    private var waiterGeneration = 0
    private var isStopping = false
    private var isPaused = false
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
            await self?.resultsEnded()
        }
        sourceTask = Task { [weak self] in
            for await event in chunks { await self?.handle(event) }
        }
        return stream
    }

    /// Order matters: drain the transcriber completely, then close the last segment(s), so the
    /// owner's closing words (which often arrive only at finish) are stored and not dropped.
    public func stop() async throws {
        isStopping = true
        await source.stop()
        await sourceTask?.value
        var closing: [MsRange] = []
        for event in segmenter.flush(atMs: lastChunkEndMs) {
            if case .segmentEnded(let range) = event { closing.append(range) } else { await closeSegments([event]) }
        }
        await transcriber.finish()
        await resultsTask?.value
        for range in closing {
            emit(.userPaused(afterMs: range.end))
            emit(.segmentClosed(takeSegment(range)))
        }
        if let first = pendingWords.first, let last = pendingWords.last {
            // Words after the last closed segment: a short closing remark, or late finals. Keep them.
            emit(.segmentClosed(takeSegment(MsRange(start: first.range.start, end: max(last.range.end, lastChunkEndMs)))))
        }
        try await sink.close()
        events?.finish()
        events = nil
    }

    /// Closes the thought in progress (the transcriber is asked to finalize) and stops capture.
    /// The source keeps its frame count, so the chunk after `resume` continues the file clock.
    public func pause() async throws {
        guard !isPaused, !isStopping else { return }
        isPaused = true
        await source.pause()
        await closeSegments(segmenter.flush(atMs: lastChunkEndMs))
        log("paused at \(lastChunkEndMs) ms")
        emit(.paused)
    }

    public func resume() async throws {
        guard isPaused else { return }
        try await source.resume()
        isPaused = false
        log("resumed at \(lastChunkEndMs) ms")
        emit(.resumed)
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
            if chunk.startMs / 5_000 != (chunk.startMs - chunk.durationMs) / 5_000 {
                log("level \(Int(chunk.levelDb)) dBFS at \(chunk.startMs) ms, pending words \(pendingWords.count)")
            }
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
                log("speech started at \(ms) ms")
                emit(.speechStarted(atMs: ms))
            case .pauseObserved(let ms):
                log("pause \(ms)")
            case .segmentEnded(let range):
                emit(.userPaused(afterMs: range.end))
                // Not awaited: a finalize that never returns must not block capture or stop().
                let transcriber = self.transcriber
                Task { await transcriber.finalize(throughMs: min(range.end, lastChunkEndMs)) }
                await waitForFinals(throughMs: range.end)
                let segment = takeSegment(range)
                log("segment \(segment.range.start)-\(segment.range.end) ms, \(segment.words.count) words")
                emit(.segmentClosed(segment))
            }
        }
    }

    /// Every unclaimed word that starts before the segment's end belongs to it. Words that start
    /// later are held for the next segment. A segment widens its start to contain a straggler
    /// (a word after the previous segment's end, or from an abandoned short blip), so every
    /// stored word starts inside its segment's range and nothing the owner said is lost.
    private func takeSegment(_ range: MsRange) -> SegmentTranscript {
        let (inside, held) = pendingWords.stablePartition { $0.range.start < range.end }
        pendingWords = held
        var range = range
        if let earliest = inside.map(\.range.start).min() { range.start = min(range.start, earliest) }
        return SegmentTranscript(range: range, text: inside.map(\.text).joined(separator: " "), words: inside)
    }

    // MARK: Transcriber results

    /// The results stream ends on its own only when the framework gave up. Audio capture goes on,
    /// so the session stays recordable; the person is told that words stopped.
    private func resultsEnded() {
        guard !isStopping else { return }
        log("transcriber results ended before stop")
        emit(.failed("The transcriber stopped. Audio is still being recorded."))
    }
    private func handle(_ result: TranscriptResult) {
        guard result.isFinal else {
            emit(.transcriptPartial(result.text))
            return
        }
        pendingWords.append(contentsOf: result.words)
        log("final \(result.words.count) words \(result.range.start)-\(result.range.end) ms")
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
        waiterGeneration += 1
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            closeWaiter = (throughMs, .now + .milliseconds(timing.finalizeTimeoutMs), waiterGeneration, continuation)
            restartGraceTimer()
        }
    }

    private func restartGraceTimer() {
        graceTimer?.cancel()
        guard let waiter = closeWaiter else { return }
        let wait = min(.milliseconds(timing.finalizeGraceMs), waiter.deadline - .now)
        let generation = waiter.generation
        graceTimer = Task { [weak self] in
            try? await Task.sleep(for: max(wait, .zero))
            guard !Task.isCancelled else { return }
            await self?.resumeCloseWaiter(ifGeneration: generation)
        }
    }

    /// A stale timer (from an earlier waiter) must not close a newer segment early.
    private func resumeCloseWaiter(ifGeneration generation: Int? = nil) {
        if let generation, closeWaiter?.generation != generation { return }
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
