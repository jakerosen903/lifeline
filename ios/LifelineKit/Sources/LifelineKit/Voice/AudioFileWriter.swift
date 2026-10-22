import AVFoundation
import CoreMedia

/// Writes chunks to a fragmented AAC m4a. Fragments are flushed every `fragmentIntervalSeconds`,
/// so a crash or kill loses at most the last fragment and the file still opens. A plain
/// `AVAudioFile` m4a writes its index only at close and is unreadable after a kill.
///
/// File time equals frames written: the writer never pads, so the source's frame counter and the
/// file agree through interruptions.
public actor AudioFileWriter: AudioSink {
    public enum Error: Swift.Error, Equatable {
        case notOpen
        case formatMismatch
        case writerFailed(String)
    }

    public static let bitRate = 48_000
    public static let fragmentIntervalSeconds: Double = 5

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var formatDescription: CMAudioFormatDescription?
    private var format: AVAudioFormat?
    public private(set) var framesWritten: AVAudioFramePosition = 0

    public init() {}

    public func open(url: URL, format: AVAudioFormat) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = CMTime(seconds: Self.fragmentIntervalSeconds, preferredTimescale: 600)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: Self.bitRate,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else { throw Error.writerFailed(writer.error?.localizedDescription ?? "startWriting") }
        writer.startSession(atSourceTime: .zero)

        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(allocator: nil, asbd: format.streamDescription, layoutSize: 0, layout: nil,
                                                    magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard status == noErr, let description else { throw Error.writerFailed("format description \(status)") }

        self.writer = writer
        self.input = input
        self.formatDescription = description
        self.format = format
        framesWritten = 0
    }

    public func write(_ chunk: AudioChunk) throws {
        guard let writer, let input, let formatDescription, let format else { throw Error.notOpen }
        guard chunk.buffer.format.sampleRate == format.sampleRate, chunk.buffer.format.channelCount == format.channelCount else {
            throw Error.formatMismatch
        }
        guard writer.status == .writing else { throw Error.writerFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)") }
        let sample = try Self.sampleBuffer(from: chunk.buffer, at: framesWritten, description: formatDescription)
        // With real-time input the encoder keeps up; a short spin covers the rare backlog.
        var spins = 0
        while !input.isReadyForMoreMediaData && spins < 200 { usleep(1_000); spins += 1 }
        guard input.append(sample) else { throw Error.writerFailed(writer.error?.localizedDescription ?? "append") }
        framesWritten += AVAudioFramePosition(chunk.buffer.frameLength)
    }

    /// Finishes the container. Harmless when already closed.
    public func close() async throws {
        guard let writer, let input else { return }
        self.writer = nil
        self.input = nil
        guard writer.status == .writing else { return }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed { throw Error.writerFailed(writer.error?.localizedDescription ?? "finishWriting") }
    }

    private static func sampleBuffer(from buffer: AVAudioPCMBuffer, at frame: AVAudioFramePosition,
                                     description: CMAudioFormatDescription) throws -> CMSampleBuffer {
        let rate = CMTimeScale(buffer.format.sampleRate)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: rate),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: rate),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var status = CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                                          formatDescription: description, sampleCount: CMItemCount(buffer.frameLength),
                                          sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                          sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw Error.writerFailed("sample buffer \(status)") }
        status = CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                                flags: 0, bufferList: buffer.audioBufferList)
        guard status == noErr else { throw Error.writerFailed("sample data \(status)") }
        return sample
    }
}
