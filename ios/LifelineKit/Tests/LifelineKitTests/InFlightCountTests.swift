import Testing
@testable import LifelineKit

/// "Adding the photo…" shows while any add is in flight (final-review I1): two picks never clear each other.

@Test func nothingInFlightAtFirst() {
    #expect(!InFlightCount().isActive)
}

@Test func aSecondAddKeepsTheLineUntilBothEnd() {
    var adds = InFlightCount()
    adds.begin()
    adds.begin()
    adds.end()
    #expect(adds.isActive, "the first add to finish does not clear the second")
    adds.end()
    #expect(!adds.isActive)
}

@Test func anUnmatchedEndNeverGoesBelowZero() {
    var adds = InFlightCount()
    adds.end()
    #expect(!adds.isActive && adds.count == 0)
    adds.begin()
    #expect(adds.isActive, "a later add still shows")
}
