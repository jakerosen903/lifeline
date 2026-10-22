import AVFoundation
@testable import LifelineKit

/// Test-only audio builders in the capture format (24 kHz mono Float32).
enum AudioFixtures {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    static func buffer(durationMs: Int, fill: (Int) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(durationMs * 24)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        b.frameLength = frames
        let p = b.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = fill(i) }
        return b
    }

    static func silence(durationMs: Int) -> AVAudioPCMBuffer { buffer(durationMs: durationMs) { _ in 0 } }

    static func sine(durationMs: Int, hz: Double = 440, amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        buffer(durationMs: durationMs) { i in amplitude * Float(sin(2 * .pi * hz * Double(i) / 24_000)) }
    }

    static func chunk(startMs: Int, durationMs: Int = 100, levelDb: Float) -> AudioChunk {
        AudioChunk(buffer: silence(durationMs: durationMs), startMs: startMs, durationMs: durationMs, levelDb: levelDb)
    }
}

func w(_ text: String, _ start: Int, _ end: Int) -> TranscribedWord {
    TranscribedWord(text: text, range: MsRange(start: start, end: end))
}
