import Testing
@testable import LifelineKit

/// Part 4: the line while photos are added and the one line when some could not be. One photo keeps the lines it had.

@Test(arguments: [
    (1, 1, "Adding the photo…"),
    (2, 5, "Adding photo 2 of 5…"),
    (1, 20, "Adding photo 1 of 20…"),
])
func progressLine(index: Int, count: Int, line: String) {
    #expect(PhotoAddProgress.line(adding: index, of: count) == line)
}

@Test func noFailureShowsNoLine() {
    #expect(PhotoAddProgress.failureLine(failed: 0, lastError: "") == nil)
}

@Test func oneFailureKeepsTodaysLine() {
    #expect(PhotoAddProgress.failureLine(failed: 1, lastError: "Lifeline cannot read this file as a photo.")
            == "Could not add this photo: Lifeline cannot read this file as a photo.")
}

@Test func severalFailuresAreCounted() {
    #expect(PhotoAddProgress.failureLine(failed: 3, lastError: "Lifeline cannot read this file as a photo.") == "3 photos could not be added.")
}

// MARK: - The picks in flight on one page

@Test func aBatchCountsThePhotoBeingAdded() {
    var batch = PhotoAddBatch()
    #expect(batch.line == nil, "nothing picked, no line")
    batch.begin(count: 3)
    #expect(batch.line == "Adding photo 1 of 3…")
    batch.finishOne()
    #expect(batch.line == "Adding photo 2 of 3…")
    batch.finishOne()
    batch.finishOne()
    #expect(batch.line == "Adding photo 3 of 3…", "the count never runs past the last photo while the pick is open")
    #expect(batch.end() == nil, "no failure, no line")
    #expect(batch.line == nil && !batch.isActive)
}

@Test func aBatchOfOneShowsTodaysLine() {
    var batch = PhotoAddBatch()
    batch.begin(count: 1)
    #expect(batch.line == "Adding the photo…")
    batch.fail("Lifeline cannot read this file as a photo.")
    batch.finishOne()
    #expect(batch.end() == "Could not add this photo: Lifeline cannot read this file as a photo.")
}

@Test func failuresAreReportedOnceAtTheEnd() {
    var batch = PhotoAddBatch()
    batch.begin(count: 3)
    batch.fail("first")
    batch.finishOne()
    batch.finishOne()
    batch.fail("third")
    batch.finishOne()
    #expect(batch.end() == "2 photos could not be added.")
    batch.begin(count: 1)
    #expect(batch.end() == nil, "a new pick starts with no failure")
}

@Test func aSecondPickJoinsTheFirstUntilBothEnd() {
    var batch = PhotoAddBatch()
    batch.begin(count: 2)
    batch.finishOne()
    batch.begin(count: 3)
    #expect(batch.line == "Adding photo 2 of 5…", "the second pick's photos join the count")
    batch.fail("unreadable")
    batch.finishOne()
    #expect(batch.end() == nil, "the first pick to end does not report while the other is open")
    #expect(batch.isActive)
    batch.finishOne(); batch.finishOne(); batch.finishOne()
    #expect(batch.end() == "Could not add this photo: unreadable")
    #expect(!batch.isActive)
}

@Test func anUnmatchedEndChangesNothing() {
    var batch = PhotoAddBatch()
    #expect(batch.end() == nil)
    batch.begin(count: 1)
    #expect(batch.isActive, "a later pick still shows")
}
