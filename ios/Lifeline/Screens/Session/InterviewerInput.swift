import Foundation
import LifelineKit

/// What the interviewer loop hears during a session. The recorder and the view model put these on one
/// stream, so the loop takes them in the order they happened: a turn's end after its start, a segment's
/// flags after the segment.
enum InterviewerInput: Sendable {
    case captureStarted(opening: String)
    case voice(VoiceEvent)
    case segmentStored(SegmentID)
    case flags(Flags, segment: SegmentID)
    /// An arc effect and the stage the arc is in after it.
    case arc(ArcEffect, stage: Stage)
    case keepGoing
    /// The Quiet control: true makes the interviewer quiet, false asks it back.
    case quiet(Bool)

    func deliver(to loop: InterviewerLoop) async {
        switch self {
        case .captureStarted(let opening): await loop.captureStarted(opening: opening)
        // "Shh" by voice: the same quiet as the tap, in the order it was heard.
        case .voice(.heard(.quiet)): await loop.setQuiet(true)
        case .voice(let event): await loop.voice(event)
        case .segmentStored(let id): await loop.segmentStored(id)
        case .flags(let flags, let segment): await loop.flags(flags, segment: segment)
        case .arc(let effect, let stage): await loop.arc(effect, stage: stage)
        case .keepGoing: await loop.keepGoing()
        case .quiet(let quiet): await loop.setQuiet(quiet)
        }
    }
}
