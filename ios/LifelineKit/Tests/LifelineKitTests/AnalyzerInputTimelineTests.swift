import Testing
@testable import LifelineKit

/// The speech analyzer rejects a buffer whose start time overlaps the previous buffer.
/// The resampler's output length jitters by a few frames, so file time alone can overlap.
struct AnalyzerInputTimelineTests {
    @Test func contiguousBuffersKeepFileTime() {
        var timeline = AnalyzerInputTimeline()
        #expect(timeline.start(fileFrame: 0, frames: 1600) == 0)
        #expect(timeline.start(fileFrame: 1600, frames: 1600) == 1600)
        #expect(timeline.start(fileFrame: 3200, frames: 1600) == 3200)
    }

    @Test func bufferLongerThanItsSlotPushesTheNextStartForward() {
        var timeline = AnalyzerInputTimeline()
        #expect(timeline.start(fileFrame: 0, frames: 1611) == 0)
        // File time says 1600, but the previous buffer already covers up to 1611.
        #expect(timeline.start(fileFrame: 1600, frames: 1600) == 1611)
    }

    @Test func gapInFileTimeJumpsForward() {
        var timeline = AnalyzerInputTimeline()
        _ = timeline.start(fileFrame: 0, frames: 1600)
        // An interruption left a hole in the file clock. Follow it; do not fill it.
        #expect(timeline.start(fileFrame: 48_000, frames: 1600) == 48_000)
    }

    @Test func shortBufferDoesNotPullTheNextStartBack() {
        var timeline = AnalyzerInputTimeline()
        _ = timeline.start(fileFrame: 0, frames: 1590)
        #expect(timeline.start(fileFrame: 1600, frames: 1600) == 1600)
    }
}
