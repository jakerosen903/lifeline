import Testing
@testable import LifelineKit

@Test func packageVersionIsSet() {
    #expect(LifelineKit.version == "0.1.0")
}
