import Synchronization
import LifelineKit

/// The question on screen and the arc's stage, for the interviewer's context. The view model writes them
/// on the main actor; the loop reads them from its own executor when it builds a request.
final class SessionSnapshot: Sendable {
    private let state: Mutex<(opening: String, stage: Stage)>

    init(opening: String, stage: Stage) { state = Mutex((opening, stage)) }

    var opening: String {
        get { state.withLock { $0.opening } }
        set { state.withLock { $0.opening = newValue } }
    }

    var stage: Stage {
        get { state.withLock { $0.stage } }
        set { state.withLock { $0.stage = newValue } }
    }
}
