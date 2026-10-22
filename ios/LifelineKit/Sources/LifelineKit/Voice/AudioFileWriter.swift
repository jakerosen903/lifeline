import AVFoundation

/// Writes chunks to an AAC m4a file. File time equals frames written: the writer never pads,
/// so the source's frame counter and the file agree through interruptions.
public actor AudioFileWriter: AudioSink {
    public enum Error: Swift.Error, Equatable {
        case notOpen
        case formatMismatch
    }

    public static let bitRate = 48_000

    private var file: AVAudioFile?
    public private(set) var framesWritten: AVAudioFramePosition = 0

    public init() {}

    public func open(url: URL, format: AVAudioFormat) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: Self.bitRate,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        framesWritten = 0
    }

    public func write(_ chunk: AudioChunk) throws {
        guard let file else { throw Error.notOpen }
        guard chunk.buffer.format.sampleRate == file.processingFormat.sampleRate,
              chunk.buffer.format.channelCount == file.processingFormat.channelCount else { throw Error.formatMismatch }
        try file.write(from: chunk.buffer)
        framesWritten += AVAudioFramePosition(chunk.buffer.frameLength)
    }

    /// Releasing the file finalizes the container. Harmless when already closed.
    public func close() {
        file = nil
    }
}
