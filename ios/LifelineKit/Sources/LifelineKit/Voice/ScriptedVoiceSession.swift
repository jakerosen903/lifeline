import AVFoundation
import Foundation

/// A voice session that plays a fixed script instead of listening. Used by UI tests and demos.
/// It writes a tone to the audio URL so playback of the "recorded" segments works.
public actor ScriptedVoiceSession: VoiceSession {
    private let script: [SegmentTranscript]
    private let intervalMs: Int
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    private var task: Task<Void, Never>?
    private var paused = false
    /// The end of the last scripted segment: the file clock a turn is stamped with.
    private var clockMs: Milliseconds = 0

    public init(script: [SegmentTranscript] = ScriptedVoiceSession.sampleScript, intervalMs: Int = 1_500) {
        self.script = script
        self.intervalMs = intervalMs
    }

    public func start(writingTo audioURL: URL) async throws -> AsyncStream<VoiceEvent> {
        try await Self.writeTone(to: audioURL, durationMs: (script.last?.range.end ?? 1_000) + 1_000)
        let (stream, c) = AsyncStream<VoiceEvent>.makeStream()
        continuation = c
        let script = self.script, intervalMs = self.intervalMs
        task = Task { [weak self] in
            for segment in script {
                try? await Task.sleep(for: .milliseconds(intervalMs))
                guard !Task.isCancelled else { return }
                while await self?.paused == true {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                }
                c.yield(.speechStarted(atMs: segment.range.start))
                c.yield(.transcriptPartial(String(segment.text.prefix(segment.text.count / 2))))
                try? await Task.sleep(for: .milliseconds(intervalMs / 3))
                c.yield(.userPaused(afterMs: segment.range.end))
                await self?.close(segment)
            }
        }
        return stream
    }

    public func stop() async throws {
        task?.cancel()
        continuation?.finish()
        continuation = nil
    }

    public func pause() async throws { paused = true; continuation?.yield(.paused) }
    public func resume() async throws { paused = false; continuation?.yield(.resumed) }

    /// The turn starts and ends at once; timed playback comes later.
    public func say(_ turn: SpokenTurn) async {
        guard let continuation, !paused else { return }
        continuation.yield(.turnStarted(turn.id, atMs: clockMs))
        continuation.yield(.turnEnded(turn.id, atMs: clockMs, interrupted: false))
    }

    public func acknowledge() async {}
    public func interrupt() async {}

    private func close(_ segment: SegmentTranscript) {
        clockMs = segment.range.end
        continuation?.yield(.segmentClosed(segment))
    }

    private static func writeTone(to url: URL, durationMs: Int) async throws {
        let writer = AudioFileWriter()
        try await writer.open(url: url, format: CaptureFormat.format)
        let frames = AVAudioFrameCount(CaptureFormat.sampleRate / 10)
        for i in 0..<(durationMs / 100) {
            let b = AVAudioPCMBuffer(pcmFormat: CaptureFormat.format, frameCapacity: frames)!
            b.frameLength = frames
            let p = b.floatChannelData![0]
            for n in 0..<Int(frames) { p[n] = 0.2 * Float(sin(2 * .pi * 330 * Double(n) / CaptureFormat.sampleRate)) }
            try await writer.write(AudioChunk(buffer: b, startMs: i * 100, durationMs: 100, levelDb: -20))
        }
        try await writer.close()
    }

    /// Invented content. Never a real person's data.
    public static let sampleScript: [SegmentTranscript] = [
        SegmentTranscript(range: MsRange(start: 0, end: 4_000), text: "the house had a blue door when I was six before Maya climbed it",
                          words: words("the house had a blue door when I was six before Maya climbed it", from: 0, to: 4_000)),
        SegmentTranscript(range: MsRange(start: 5_500, end: 9_000), text: "my sister Maya climbed it in 1998 every summer",
                          words: words("my sister Maya climbed it in 1998 every summer", from: 5_500, to: 9_000)),
        SegmentTranscript(range: MsRange(start: 10_500, end: 13_000), text: "we moved away the year before she was born",
                          words: words("we moved away the year before she was born", from: 10_500, to: 13_000)),
    ]

    /// Entities (M7): a fact about a thing, a dated moment with it, an idea told twice years
    /// apart, and a thing nothing else carries.
    public static let entityScript: [SegmentTranscript] = [
        SegmentTranscript(range: MsRange(start: 0, end: 2_500), text: "the house had a blue door",
                          words: words("the house had a blue door", from: 0, to: 2_500)),
        SegmentTranscript(range: MsRange(start: 3_500, end: 6_000), text: "we painted the house in 1995",
                          words: words("we painted the house in 1995", from: 3_500, to: 6_000)),
        SegmentTranscript(range: MsRange(start: 7_000, end: 10_000), text: "in 1990 I thought hard work was everything",
                          words: words("in 1990 I thought hard work was everything", from: 7_000, to: 10_000)),
        SegmentTranscript(range: MsRange(start: 11_000, end: 14_000), text: "in 2020 I saw hard work differently",
                          words: words("in 2020 I saw hard work differently", from: 11_000, to: 14_000)),
        SegmentTranscript(range: MsRange(start: 15_000, end: 17_000), text: "the old shed out back",
                          words: words("the old shed out back", from: 15_000, to: 17_000)),
    ]

    private static func words(_ text: String, from start: Int, to end: Int) -> [TranscribedWord] {
        let tokens = text.split(separator: " ").map(String.init)
        let step = (end - start) / tokens.count
        return tokens.enumerated().map { i, t in
            TranscribedWord(text: t, range: MsRange(start: start + i * step, end: start + (i + 1) * step - 50))
        }
    }
}
