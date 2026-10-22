import Testing
@testable import LifelineKit

@Test func availabilityDecision() {
    #expect(TranscriberAvailability.decide(isSupported: true, isInstalled: true) == .ready)
    #expect(TranscriberAvailability.decide(isSupported: true, isInstalled: false) == .needsDownload)
    #expect(TranscriberAvailability.decide(isSupported: false, isInstalled: false) == .unsupportedLocale)
    #expect(TranscriberAvailability.decide(isSupported: false, isInstalled: true) == .unsupportedLocale)
}
