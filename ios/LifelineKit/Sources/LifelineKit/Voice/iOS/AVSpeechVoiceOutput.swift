#if os(iOS)
import AVFoundation
import Synchronization

/// The system voice. Each turn is rendered with `AVSpeechSynthesizer.write`, converted to the
/// source's playback format and played on the capture engine, so echo cancellation hears it.
///
/// Each `play` has its own token and its own synthesizer, and a new `play` cuts the one before it.
/// Callbacks from a cut playback's synthesizer and player carry its token and are dropped, so they
/// cannot end a newer turn. `stop` cuts the playback that is current when it runs. The session ends
/// its turn before it calls `stop` and plays the next turn after `stop` returns; only a `say` that
/// races an `interrupt()` in the hop into `stop` could have its new turn cut.
/// `.started` comes when the source accepts the first buffer for the player; a refused first
/// buffer ends the stream with no events. A turn that renders no audio, or
/// whose synthesizer goes silent, finishes with no events: the session then treats it as unheard.
///
/// Threads: buffer callbacks run on the synthesizer's thread, completions on the source's; both
/// touch `State` only under its mutex.
public final class AVSpeechVoiceOutput: VoiceOutput, @unchecked Sendable {
    /// With no buffer from the synthesizer for this long, and nothing left to play, the turn ends.
    private static let stallTimeout: Duration = .seconds(3)

    /// `@unchecked`: touched only under `state`'s lock.
    private struct Playback: @unchecked Sendable {
        let token: Int
        let synthesizer: AVSpeechSynthesizer
        let continuation: AsyncStream<PlaybackEvent>.Continuation
        var converter: AVAudioConverter?
        var started = false
        var renderingDone = false
        /// Buffers handed to the source that have not played yet.
        var outstanding = 0
        var lastBufferAt: ContinuousClock.Instant = .now
        var watchdog: Task<Void, Never>?
    }

    private struct State: Sendable {
        var nextToken = 0
        var current: Playback?
    }

    private let source: AVAudioEngineSource
    private let voice: AVSpeechSynthesisVoice?
    private let state = Mutex(State())

    public init(source: AVAudioEngineSource) {
        self.source = source
        voice = Self.bestVoice()
    }

    public func play(_ text: String) -> AsyncStream<PlaybackEvent> {
        let (stream, continuation) = AsyncStream<PlaybackEvent>.makeStream()
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let (token, previous) = state.withLock { state -> (Int, AVSpeechSynthesizer?) in
            // One turn at a time: the one before is cut before any of this turn's audio is scheduled.
            let previous = state.current.map { cut($0) }
            state.nextToken += 1
            state.current = Playback(token: state.nextToken, synthesizer: synthesizer, continuation: continuation)
            return (state.nextToken, previous)
        }
        previous?.stopSpeaking(at: .immediate)
        let watchdog = watchdog(token)
        state.withLock { state in
            if state.current?.token == token { state.current?.watchdog = watchdog } else { watchdog.cancel() }
        }
        synthesizer.write(utterance) { [weak self] buffer in
            self?.rendered(buffer, token: token)
        }
        return stream
    }

    /// Cuts the playback that is current now. One that a later `play` replaced is already cut.
    public func stop() async {
        let synthesizer = state.withLock { state -> AVSpeechSynthesizer? in
            defer { state.current = nil }
            return state.current.map { cut($0) }
        }
        synthesizer?.stopSpeaking(at: .immediate)
    }

    // MARK: Private

    /// Under the lock, for a playback leaving `state.current`. Stops the player (ordered on the
    /// source before any later buffer) and ends the stream. Returns the synthesizer, which the
    /// caller stops after the lock: stopping can call back into `rendered`.
    private func cut(_ playback: Playback) -> AVSpeechSynthesizer {
        source.stopPlayback()
        end(playback, completed: false)
        return playback.synthesizer
    }

    /// Under the lock, for a playback leaving `state.current`. A started turn reports how it
    /// ended; an unstarted one ends with no events.
    private func end(_ playback: Playback, completed: Bool) {
        playback.watchdog?.cancel()
        if playback.started { playback.continuation.yield(.finished(completed: completed)) }
        playback.continuation.finish()
    }

    /// The synthesizer's callback. The last buffer is empty: it marks the end of rendering.
    private func rendered(_ buffer: AVAudioBuffer, token: Int) {
        nonisolated(unsafe) let buffer = buffer   // the synthesizer hands it over and does not reuse it
        state.withLock { state in
            guard var playback = state.current, playback.token == token else { return }
            playback.lastBufferAt = .now
            defer { if state.current?.token == token { state.current = playback } }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                playback.renderingDone = true
                if playback.outstanding == 0 {
                    state.current = nil
                    end(playback, completed: true)
                }
                return
            }
            guard let converted = convert(pcm, with: &playback.converter) else { return }
            playback.outstanding += 1
            // Under the lock, so a stop that comes later is ordered after this buffer on the source.
            source.schedule(converted,
                            accepted: { [weak self] accepted in self?.accepted(accepted, token: token) },
                            played: { [weak self] in self?.played(token: token) })
        }
    }

    /// The source took a buffer for the player (true), or refused it (false: paused, interrupted,
    /// stopped). The first accepted buffer starts the turn. A refusal ends it: with no events if
    /// nothing was accepted yet, so the session knows the turn was not heard.
    private func accepted(_ accepted: Bool, token: Int) {
        let refused = state.withLock { state -> AVSpeechSynthesizer? in
            guard var playback = state.current, playback.token == token else { return nil }
            guard accepted else {
                state.current = nil
                end(playback, completed: false)
                return playback.synthesizer
            }
            if !playback.started {
                playback.started = true
                playback.continuation.yield(.started)
                state.current = playback
            }
            return nil
        }
        refused?.stopSpeaking(at: .immediate)
    }

    /// An accepted buffer played, or was cut by a player stop.
    private func played(token: Int) {
        state.withLock { state in
            guard var playback = state.current, playback.token == token else { return }
            playback.outstanding -= 1
            if playback.renderingDone, playback.outstanding == 0 {
                state.current = nil
                end(playback, completed: true)
            } else {
                state.current = playback
            }
        }
    }

    /// Ends a turn whose synthesizer stopped calling back without its last buffer, or never began.
    private func watchdog(_ token: Int) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                if self.endIfStalled(token) { return }
            }
        }
    }

    /// True when the playback for `token` is gone, or was stalled and is now ended.
    private func endIfStalled(_ token: Int) -> Bool {
        let (gone, stalled) = state.withLock { state -> (Bool, AVSpeechSynthesizer?) in
            guard let playback = state.current, playback.token == token else { return (true, nil) }
            guard playback.outstanding == 0, ContinuousClock.now - playback.lastBufferAt > Self.stallTimeout else { return (false, nil) }
            state.current = nil
            end(playback, completed: false)
            return (true, playback.synthesizer)
        }
        if let stalled {
            print("[voice] the synthesizer stalled; the turn ends")
            stalled.stopSpeaking(at: .immediate)
        }
        return gone
    }

    /// The synthesizer's buffers (often 22.05 kHz Int16) in the source's playback format. One
    /// converter per turn keeps the resampler's state across buffers.
    private func convert(_ input: AVAudioPCMBuffer, with converter: inout AVAudioConverter?) -> AVAudioPCMBuffer? {
        let output = source.playbackFormat
        if converter?.inputFormat != input.format { converter = AVAudioConverter(from: input.format, to: output) }
        guard let converter else { return nil }
        let ratio = output.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: buffer, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, buffer.frameLength > 0 else { return nil }
        return buffer
    }

    /// The best installed English voice (`VoicePicker`); nil lets the system choose.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let infos = installed.map { voice in
            VoiceInfo(identifier: voice.identifier, language: voice.language, quality: quality(voice.quality))
        }
        guard let best = VoicePicker.best(infos) else { return AVSpeechSynthesisVoice(language: "en-US") }
        return AVSpeechSynthesisVoice(identifier: best.identifier)
    }

    private static func quality(_ quality: AVSpeechSynthesisVoiceQuality) -> VoiceInfo.Quality {
        switch quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .default
        }
    }
}
#endif
