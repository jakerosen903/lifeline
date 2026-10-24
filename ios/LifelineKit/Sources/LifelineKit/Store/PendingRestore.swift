import Foundation

/// A restore that is staged and waits for the next launch to be applied (M6).
public struct PendingRestore: Sendable, Equatable {
    public var manifest: BackupManifest
    /// The copy of what was on the phone before, written to Documents where Files can see it.
    public var safetyCopy: URL

    public init(manifest: BackupManifest, safetyCopy: URL) { self.manifest = manifest; self.safetyCopy = safetyCopy }
}
