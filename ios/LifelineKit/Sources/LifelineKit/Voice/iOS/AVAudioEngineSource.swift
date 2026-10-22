#if os(iOS)
import AVFoundation

/// The microphone. One tap on the input node; each buffer is converted to `CaptureFormat`,
/// stamped with the running frame count (the file clock) and measured for level.
///
/// Interruptions pause the engine and emit `.interrupted`; when the system allows, the engine
/// restarts and `.resumed` is emitted. The frame counter never jumps: it counts delivered frames.
public final class AVAudioEngineSource: AudioSource, @unchecked Sendable {
    public let format = CaptureFormat.format

    private let engine = AVAudioEngine()
    private let bufferMs: Int
    private var continuation: AsyncStream<AudioSourceEvent>.Continuation?
    private var observers: [NSObjectProtocol] = []
    private var converter: AVAudioConverter?
    /// Frames delivered so far in `CaptureFormat`. Touched only on the tap's thread.
    private var framesDelivered: AVAudioFramePosition = 0

    public init(bufferMs: Int = 100) {
        self.bufferMs = bufferMs
    }

    public func start() async throws -> AsyncStream<AudioSourceEvent> {
        let (stream, continuation) = AsyncStream<AudioSourceEvent>.makeStream()
        self.continuation = continuation
        framesDelivered = 0
        try installTap()
        observeSession()
        try engine.start()
        return stream
    }

    public func stop() async {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    // MARK: Tap

    private func installTap() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw SourceError.noInput
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw SourceError.cannotConvert
        }
        self.converter = converter
        let frames = AVAudioFrameCount(inputFormat.sampleRate * Double(bufferMs) / 1_000)
        input.installTap(onBus: 0, bufferSize: frames, format: inputFormat) { [weak self] buffer, _ in
            self?.deliver(buffer)
        }
    }

    private func deliver(_ input: AVAudioPCMBuffer) {
        guard let converter, let continuation else { return }
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0 else { return }

        let startMs = CaptureFormat.milliseconds(forFrames: framesDelivered)
        framesDelivered += AVAudioFramePosition(output.frameLength)
        let durationMs = CaptureFormat.milliseconds(forFrames: framesDelivered) - startMs
        continuation.yield(.chunk(AudioChunk(buffer: output, startMs: startMs, durationMs: durationMs, levelDb: rmsDb(output))))
    }

    // MARK: Session notifications

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.handleConfigurationChange()
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            engine.pause()
            continuation?.yield(.interrupted)
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            guard options.contains(.shouldResume) else { return }
            restartEngine()
        @unknown default:
            break
        }
    }

    /// A route change (headset unplugged, Bluetooth connected) can change the input format.
    /// Reinstall the tap for the new format and keep counting frames.
    private func handleConfigurationChange() {
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTap()
            restartEngine()
        } catch {
            continuation?.yield(.interrupted)
        }
    }

    private func restartEngine() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            continuation?.yield(.resumed)
        } catch {
            // Stay interrupted; the owner sees "Paused" and can stop the session.
        }
    }

    public enum SourceError: Error {
        case noInput
        case cannotConvert
    }
}
#endif
