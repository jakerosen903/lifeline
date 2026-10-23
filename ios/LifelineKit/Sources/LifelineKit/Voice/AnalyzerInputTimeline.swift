/// Start times for buffers handed to a speech analyzer, in analyzer frames.
///
/// The analyzer rejects a buffer that starts before the previous one ends. The resampler that
/// feeds it emits a jittery number of frames per buffer, so a stamp taken from the file clock
/// alone can land inside the previous buffer. Each start is therefore the later of the file
/// time and the end of the previous buffer: a gap in the file clock (an interruption) is
/// followed, an overrun is pushed forward by a few frames, and the two never overlap.
struct AnalyzerInputTimeline {
    private var nextFreeFrame: Int64 = 0

    mutating func start(fileFrame: Int64, frames: Int) -> Int64 {
        let start = max(fileFrame, nextFreeFrame)
        nextFreeFrame = start + Int64(frames)
        return start
    }
}
