#if os(iOS)
import AVFoundation
import CoreMedia
import Speech

/// On-device transcription with the iOS 26 Speech framework. Every buffer is stamped with its
/// file time, so word timestamps are file timestamps.
public actor SpeechAnalyzerTranscriber: Transcriber {
    public enum Error: Swift.Error {
        case unsupportedLocale(Locale)
        case noCompatibleFormat
    }

    private let locale: Locale
    private let onStatus: @Sendable (TranscriberAvailability) -> Void
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?

    public init(locale: Locale = .current, onStatus: @escaping @Sendable (TranscriberAvailability) -> Void = { _ in }) {
        self.locale = locale
        self.onStatus = onStatus
    }

    public func start(format: AVAudioFormat) async throws -> AsyncStream<TranscriptResult> {
        // `Locale.current` may carry region or calendar extensions; the framework knows the
        // equivalent locale it actually supports. Use that one everywhere.
        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        let installed = await SpeechTranscriber.installedLocales.contains { installedLocale in
            supportedLocale.map { $0.identifier(.bcp47) == installedLocale.identifier(.bcp47) } ?? false
        }
        let availability = TranscriberAvailability.decide(isSupported: supportedLocale != nil, isInstalled: installed)
        onStatus(availability)
        guard let supportedLocale else { throw Error.unsupportedLocale(locale) }

        let transcriber = SpeechTranscriber(locale: supportedLocale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        self.transcriber = transcriber
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        onStatus(.ready)

        guard let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format) else {
            throw Error.noCompatibleFormat
        }
        analyzerFormat = best
        if best != format {
            converter = AVAudioConverter(from: format, to: best)
        }

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = inputContinuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: inputStream)

        let (results, resultsContinuation) = AsyncStream<TranscriptResult>.makeStream()
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    resultsContinuation.yield(Self.convert(result))
                }
            } catch {
                // The stream ends; the session's stop() will finish normally.
            }
            resultsContinuation.finish()
        }
        return results
    }

    /// The chunk's file time is passed explicitly, so analyzer time equals file time by
    /// construction even if a conversion drops frames or the converter adds priming latency.
    public func feed(_ chunk: AudioChunk) {
        guard let input else { return }
        let buffer = converter == nil ? chunk.buffer : converted(chunk.buffer)
        guard let buffer, buffer.frameLength > 0 else { return }
        input.yield(AnalyzerInput(buffer: buffer, bufferStartTime: CMTime(value: CMTimeValue(chunk.startMs), timescale: 1_000)))
    }

    public func finalize(throughMs: Milliseconds) async {
        try? await analyzer?.finalize(through: CMTime(value: CMTimeValue(throughMs), timescale: 1_000))
    }

    public func finish() async {
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
    }

    private func converted(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let analyzerFormat else { return buffer }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    private static func convert(_ result: SpeechTranscriber.Result) -> TranscriptResult {
        TranscriptResult(text: String(result.text.characters),
                         words: result.isFinal ? WordRuns.words(from: result.text) : [],
                         range: MsRange(start: WordRuns.milliseconds(result.range.start), end: WordRuns.milliseconds(result.range.end)),
                         isFinal: result.isFinal)
    }
}
#endif
