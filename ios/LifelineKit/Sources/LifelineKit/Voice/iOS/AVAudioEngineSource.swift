#if os(iOS)
import AVFoundation
import Synchronization
import UIKit

/// The microphone. One tap on the input node; each buffer is converted to `CaptureFormat`,
/// stamped with the running frame count (the file clock) and measured for level.
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

    private let engine = AVAudioEngine()
    private let bufferMs: Int
    private let tap = Mutex(TapState())
    private let control = DispatchQueue(label: "lifeline.audio-source")
    private var observers: [NSObjectProtocol] = []
    /// Guarded by `control`.
    private var isInterrupted = false
    private var isStopped = false
    private var isPaused = false

    public init(bufferMs: Int = 100) {
        self.bufferMs = bufferMs
    }

    public func start() async throws -> AsyncStream<AudioSourceEvent> {
        let (stream, continuation) = AsyncStream<AudioSourceEvent>.makeStream()
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            control.async {
                do {
                    self.tap.withLock { $0 = TapState(converter: nil, continuation: continuation, framesDelivered: 0) }
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
               AVAudioSession.InterruptionReason(rawValue: reasonRaw) == .appWasSuspended { return }
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
    private func handleConfigurationChange() {
        guard !isStopped else { return }
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
