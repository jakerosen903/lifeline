import Testing
@testable import LifelineKit

@Test func theCaptionSaysOnlyTheDate() {
    #expect(PhotoCaption.taken(PhotoTakenAt(stored: "2012-06-14T15:32:10")) == "taken 14 June 2012")
    #expect(PhotoCaption.taken(PhotoTakenAt(stored: "2012-01-05T00:00:00")) == "taken 5 January 2012", "no leading zero on the day")
    #expect(PhotoCaption.taken(nil) == nil)
}

@Test func theLabelSaysWhereThePersonPutIt() {
    #expect(PhotoCaption.label(title: "Maya", isOwner: false, isMemory: false) == "Photo of Maya")
    #expect(PhotoCaption.label(title: "Jordan", isOwner: true, isMemory: false) == "Photo of you")
    #expect(PhotoCaption.label(title: "The tree house", isOwner: false, isMemory: true) == "Photo for The tree house")
}
