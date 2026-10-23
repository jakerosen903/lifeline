import AVFoundation
import Testing
@testable import LifelineKit

private func tempM4A() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
}

private func chunk(_ buffer: AVAudioPCMBuffer, startMs: Int) -> AudioChunk {
    AudioChunk(buffer: buffer, startMs: startMs, durationMs: Int(buffer.frameLength) / 24, levelDb: rmsDb(buffer))
}

@Test func writesPlayableM4AOfExpectedDuration() async throws {
    let url = tempM4A()
    let w = AudioFileWriter()
    try await w.open(url: url, format: CaptureFormat.format)
    for i in 0..<30 { try await w.write(chunk(AudioFixtures.sine(durationMs: 100), startMs: i * 100)) }   // 3 s
    try await w.close()
    let f = try AVAudioFile(forReading: url)
    let seconds = Double(f.length) / f.fileFormat.sampleRate
    #expect(abs(seconds - 3.0) < 0.1)
    #expect(f.fileFormat.sampleRate == 24_000 && f.fileFormat.channelCount == 1)
    #expect(f.fileFormat.formatDescription.audioStreamBasicDescription?.mFormatID == kAudioFormatMPEG4AAC)
}

@Test func appendAfterGapKeepsFileTimeContinuous() async throws {
    // The writer never pads silence. File time == frames written. The source's clock counts only
    // delivered frames, so a 4 s interruption between these two chunks leaves a 2 s file whose
    // second second is the chunk the source stamped at startMs 1_000 (not 5_000).
    let url = tempM4A()
    let w = AudioFileWriter()
    try await w.open(url: url, format: CaptureFormat.format)
    try await w.write(chunk(AudioFixtures.sine(durationMs: 1_000), startMs: 0))
    try await w.write(chunk(AudioFixtures.sine(durationMs: 1_000), startMs: 1_000))
    try await w.close()
    let f = try AVAudioFile(forReading: url)
    #expect(abs(Double(f.length) / f.fileFormat.sampleRate - 2.0) < 0.1)
    #expect(try await w.framesWritten == 48_000)
}

@Test func writeBeforeOpenThrows() async throws {
    let w = AudioFileWriter()
    await #expect(throws: AudioFileWriter.Error.self) {
        try await w.write(chunk(AudioFixtures.silence(durationMs: 100), startMs: 0))
    }
}

@Test func closeTwiceIsHarmless() async throws {
    let w = AudioFileWriter()
    try await w.open(url: tempM4A(), format: CaptureFormat.format)
    try await w.close()
    try await w.close()
}

@Test func rmsDbOfSilenceIsFloor() {
    #expect(rmsDb(AudioFixtures.silence(durationMs: 100)) <= -99)
}

@Test func rmsDbOfFullScaleSineIsNearMinus3() {
    #expect(abs(rmsDb(AudioFixtures.sine(durationMs: 100, amplitude: 1)) - (-3.01)) < 0.3)
}

@Test func rmsDbOfEmptyBufferIsFloor() {
    let b = AVAudioPCMBuffer(pcmFormat: CaptureFormat.format, frameCapacity: 10)!
    b.frameLength = 0
    #expect(rmsDb(b) <= -99)
}

@Test func captureFormatIs24kMonoFloat() {
    let f = CaptureFormat.format
    #expect(f.sampleRate == 24_000 && f.channelCount == 1 && f.commonFormat == .pcmFormatFloat32 && !f.isInterleaved)
}

@Test func fileCopiedBeforeCloseIsReadable() async throws {
    // A crash or kill never calls close(). What is on disk must still open, minus at most one fragment.
    let url = tempM4A()
    let w = AudioFileWriter()
    try await w.open(url: url, format: CaptureFormat.format)
    let seconds = 12
    for i in 0..<(seconds * 10) { try await w.write(chunk(AudioFixtures.sine(durationMs: 100), startMs: i * 100)) }
    try await Task.sleep(for: .milliseconds(500))
    let copy = tempM4A()
    try FileManager.default.copyItem(at: url, to: copy)
    let f = try AVAudioFile(forReading: copy)
    let readable = Double(f.length) / f.fileFormat.sampleRate
    #expect(readable >= Double(seconds) - AudioFileWriter.fragmentIntervalSeconds - 0.5)
    try await w.close()
}
