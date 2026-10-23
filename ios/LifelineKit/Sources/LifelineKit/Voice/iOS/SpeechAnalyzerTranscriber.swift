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
    private let log: @Sendable (String) -> Void
    private var fedBuffers = 0
    private var timeline = AnalyzerInputTimeline()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?

    public init(locale: Locale = .current,
                onStatus: @escaping @Sendable (TranscriberAvailability) -> Void = { _ in },
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.locale = locale
        self.onStatus = onStatus
        self.log = log
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
        log("transcriber locale \(supportedLocale?.identifier(.bcp47) ?? "none") installed \(installed)")
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
        log("analyzer format \(best.sampleRate) Hz, \(best.channelCount) ch, \(best.commonFormat.rawValue), interleaved \(best.isInterleaved); capture \(format.sampleRate) Hz \(format.commonFormat.rawValue)")
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
                    log("result final \(result.isFinal) \(result.text.characters.count) chars")
                    resultsContinuation.yield(Self.convert(result))
                }
                log("results stream ended")
            } catch {
                log("results stream failed: \(error)")
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
        guard let buffer, buffer.frameLength > 0 else {
            log("feed dropped buffer at \(chunk.startMs) ms (converted \(buffer?.frameLength ?? 0) frames)")
            return
        }
        let rate = Int64(buffer.format.sampleRate)
        let fileFrame = Int64(chunk.startMs) * rate / 1_000
        let startFrame = timeline.start(fileFrame: fileFrame, frames: Int(buffer.frameLength))
        fedBuffers += 1
        if fedBuffers <= 3 { log("fed \(buffer.frameLength) frames at \(chunk.startMs) ms, stamped frame \(startFrame)") }
        input.yield(AnalyzerInput(buffer: buffer, bufferStartTime: CMTime(value: startFrame, timescale: CMTimeScale(rate))))
    }

    public func finalize(throughMs: Milliseconds) async {
        do { try await analyzer?.finalize(through: CMTime(value: CMTimeValue(throughMs), timescale: 1_000)) }
        catch { log("finalize failed: \(error)") }
    }

    public func finish() async {
        input?.finish()
        input = nil
        do { try await analyzer?.finalizeAndFinishThroughEndOfInput() } catch { log("finish failed: \(error)") }
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
