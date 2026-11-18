import os

/// A checked continuation that resumes at most once, from any thread. PhotoKit can call a result handler more than
/// once, and a cancelled task resumes from its cancellation handler; the first caller wins, later calls do nothing.
/// A second resume of a `CheckedContinuation` would trap.
final class ResumeOnce<Value: Sendable>: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<Value, Never>?>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func resume(_ value: Value) {
        // Taken out under the lock, resumed outside it: the resumed task never runs while the lock is held.
        let taken = continuation.withLock { held in
            defer { held = nil }
            return held
        }
        taken?.resume(returning: value)
    }
}
