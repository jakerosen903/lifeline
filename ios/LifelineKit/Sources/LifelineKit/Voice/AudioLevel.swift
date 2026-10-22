import AVFoundation

/// The format every chunk is converted to right after the tap: 24 kHz, mono, Float32.
/// The file and the transcriber both consume this, so there is one clock and one converter.
public enum CaptureFormat {
    public static let sampleRate: Double = 24_000
    public static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    public static func milliseconds(forFrames frames: AVAudioFramePosition) -> Milliseconds {
        Int((Double(frames) * 1_000 / sampleRate).rounded())
    }
}

/// RMS level of the first channel in dBFS, clamped to -100 for silence or an empty buffer.
public func rmsDb(_ buffer: AVAudioPCMBuffer) -> Float {
    let floor: Float = -100
    guard buffer.frameLength > 0, let data = buffer.floatChannelData?[0] else { return floor }
    var sum: Float = 0
    for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
    let rms = (sum / Float(buffer.frameLength)).squareRoot()
    guard rms > 0 else { return floor }
    return max(floor, 20 * log10(rms))
}
