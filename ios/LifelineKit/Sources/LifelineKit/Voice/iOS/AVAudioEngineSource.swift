#if os(iOS)
import AVFoundation
import Synchronization
import UIKit

/// The microphone, and the speaker when the app can speak. One tap on the input node; each buffer
/// is converted to `CaptureFormat`, stamped with the running frame count (the file clock) and
/// measured for level.
///
/// With `voiceProcessing`, the input node cancels echo, and a player node on the same engine plays
/// the app's voice, so the canceller hears what it must remove. Without it, nothing plays: speech
/// with no echo cancellation would reach the recording. Pause, an interruption, a configuration
/// change and stop all stop playback, so a waiting `schedule` returns.
///
/// Threads: the tap callback runs on an audio thread and only touches `TapState` under its
/// mutex. Everything else (start, stop, notifications, restarts) runs on one serial queue.
///
/// Interruptions pause the engine and emit `.interrupted`. The engine restarts when the
/// interruption ends (with or without `.shouldResume`), when the app becomes active again,
/// or when media services reset. The frame counter never jumps: it counts delivered frames.
public final class AVAudioEngineSource: AudioSource, @unchecked Sendable {
    public enum SourceError: Error {
        case noInput
        case cannotConvert
    }

    private struct TapState {
        var converter: AVAudioConverter?
        var continuation: AsyncStream<AudioSourceEvent>.Continuation?
        var framesDelivered: AVAudioFramePosition = 0
    }

    public let format = CaptureFormat.format
    /// What `schedule` takes. The mixer converts it to the output's rate.
    public let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let bufferMs: Int
    private let voiceProcessing: Bool
    private let tap = Mutex(TapState())
    private let control = DispatchQueue(label: "lifeline.audio-source")
    private var observers: [NSObjectProtocol] = []
    /// Guarded by `control`.
    private var isInterrupted = false
    private var isStopped = false
    private var isPaused = false

    public init(bufferMs: Int = 100, voiceProcessing: Bool = false) {
        self.bufferMs = bufferMs
        self.voiceProcessing = voiceProcessing
    }

    public func start() async throws -> AsyncStream<AudioSourceEvent> {
        let (stream, continuation) = AsyncStream<AudioSourceEvent>.makeStream()
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            control.async {
                do {
                    self.tap.withLock { $0 = TapState(converter: nil, continuation: continuation, framesDelivered: 0) }
                    // Voice processing changes the input format, so it comes before the tap reads it.
                    if self.voiceProcessing { try self.attachPlayer() }
                    try self.installTap()
                    self.observeSession()
                    try self.engine.start()
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
        return stream
    }

    public func pause() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            control.async {
                guard !self.isStopped else { done.resume(); return }
                self.isPaused = true
                self.stopPlayer()   // a paused engine would hold the rest of the turn for after the resume
                self.engine.pause()
                done.resume()
            }
        }
    }

    public func resume() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            control.async {
                guard !self.isStopped else { done.resume(); return }
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    if !self.engine.isRunning { try self.engine.start() }
                    self.isPaused = false
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    public func stop() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            control.async {
                self.isStopped = true
                for o in self.observers { NotificationCenter.default.removeObserver(o) }
                self.observers = []
                self.engine.inputNode.removeTap(onBus: 0)
                self.stopPlayer()
                self.engine.stop()
                let continuation = self.tap.withLock { state in
                    defer { state.continuation = nil; state.converter = nil }
                    return state.continuation
                }
                continuation?.finish()
                done.resume()
            }
        }
    }

    // MARK: Playback

    /// Plays `buffer` after the buffers scheduled before it. Returns true when it has played or
    /// was cut by `stopPlayback` (or a pause, an interruption, a configuration change or stop), and
    /// false at once when the engine cannot play: no voice processing, paused, interrupted, stopped.
    @discardableResult
    public func schedule(_ buffer: AVAudioPCMBuffer) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            schedule(buffer, accepted: { if !$0 { done.resume(returning: false) } },
                     played: { done.resume(returning: true) })
        }
    }

    /// `schedule` for a caller that cannot wait, such as a synthesizer's buffer callback. Calls on
    /// one thread play in call order. `accepted` runs once on the control queue: true just before
    /// the buffer goes to the player, false when it is refused. Only an accepted buffer later calls
    /// `played`, once, on an audio thread or the control queue.
    public func schedule(_ buffer: AVAudioPCMBuffer, accepted: @escaping @Sendable (Bool) -> Void,
                         played: @escaping @Sendable () -> Void) {
        nonisolated(unsafe) let buffer = buffer   // handed to the player and not touched again
        control.async {
            guard self.player.engine != nil, !self.isStopped, !self.isPaused, !self.isInterrupted,
                  self.engine.isRunning else { accepted(false); return }
            accepted(true)
            self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in played() }
            if !self.player.isPlaying { self.player.play() }
        }
    }

    /// Cuts what is playing and drops what is scheduled. Each waiting `schedule` returns.
    /// Ordered with `schedule`: a buffer scheduled after this call still plays.
    public func stopPlayback() {
        control.async { self.stopPlayer() }
    }

    /// Control queue, engine stopped. Once per source.
    private func attachPlayer() throws {
        guard player.engine == nil else { return }
        try engine.inputNode.setVoiceProcessingEnabled(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
    }

    /// Control queue. A player that was never attached has nothing to stop.
    private func stopPlayer() {
        guard player.engine != nil else { return }
        player.stop()
    }

    // MARK: Tap (control queue)

    private func installTap() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw SourceError.noInput }
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else { throw SourceError.cannotConvert }
        tap.withLock { $0.converter = converter }
        let frames = AVAudioFrameCount(inputFormat.sampleRate * Double(bufferMs) / 1_000)
        input.installTap(onBus: 0, bufferSize: frames, format: inputFormat) { [weak self] buffer, _ in
            self?.deliver(buffer)
        }
    }

    // MARK: Tap callback (audio thread)

    private func deliver(_ input: AVAudioPCMBuffer) {
        guard let (converter, continuation) = tap.withLock({ s in s.converter.flatMap { c in s.continuation.map { (c, $0) } } }) else { return }
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

        let (startMs, durationMs) = tap.withLock { s -> (Milliseconds, Milliseconds) in
            let start = CaptureFormat.milliseconds(forFrames: s.framesDelivered)
            s.framesDelivered += AVAudioFramePosition(output.frameLength)
            return (start, CaptureFormat.milliseconds(forFrames: s.framesDelivered) - start)
        }
        continuation.yield(.chunk(AudioChunk(buffer: output, startMs: startMs, durationMs: durationMs, levelDb: rmsDb(output))))
    }

    // MARK: Session notifications (control queue)

    private func observeSession() {
        let center = NotificationCenter.default
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = control
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: queue) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: queue) { [weak self] _ in
            self?.handleConfigurationChange()
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: queue) { [weak self] _ in
            self?.handleConfigurationChange()
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: queue) { [weak self] _ in
            guard let self, self.isInterrupted else { return }
            self.restartEngine()
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard !isStopped, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // A suspension notice arrives when the app wakes; the engine was already paused by the system.
            if let reasonRaw = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt,
               AVAudioSession.InterruptionReason(rawValue: reasonRaw) == .appWasSuspended {
                stopPlayer()   // no turn may wait on a player the system has silenced
                return
            }
            stopPlayer()
            engine.pause()
            markInterrupted()
        case .ended:
            // iOS often omits .shouldResume after a call; a record-category app may still reactivate.
            restartEngine()
        @unknown default:
            break
        }
    }

    /// A route change (headset unplugged, Bluetooth connected) or a media-services reset can
    /// change the input format. Reinstall the tap for the new format and keep counting frames.
    /// The engine has stopped, so the turn that was playing is cut.
    private func handleConfigurationChange() {
        guard !isStopped else { return }
        stopPlayer()
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTap()
            restartEngine()
        } catch {
            markInterrupted()
        }
    }

    private func markInterrupted() {
        guard !isInterrupted else { return }
        isInterrupted = true
        yield(.interrupted)
    }

    private func restartEngine() {
        guard !isStopped, !isPaused else { return }   // a paused person stays paused through an interruption
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            if isInterrupted {
                isInterrupted = false
                yield(.resumed)
            }
        } catch {
            markInterrupted()   // stays Paused; didBecomeActive will try again
        }
    }

    private func yield(_ event: AudioSourceEvent) {
        tap.withLock { $0.continuation }?.yield(event)
    }
}
#endif
