/// Whether on-device transcription can run for a locale. Pure so it is testable on macOS.
public enum TranscriberAvailability: Equatable, Sendable {
    case ready
    case needsDownload
    case unsupportedLocale

    public static func decide(isSupported: Bool, isInstalled: Bool) -> TranscriberAvailability {
        guard isSupported else { return .unsupportedLocale }
        return isInstalled ? .ready : .needsDownload
    }
}
