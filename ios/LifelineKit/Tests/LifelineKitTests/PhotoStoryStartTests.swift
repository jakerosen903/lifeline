import Testing
@testable import LifelineKit

@Test func route() {
    #expect(PhotoStoryStart.route(access: .notAsked, photoCount: 0) == .explain, "the first tap explains before the system asks")
    #expect(PhotoStoryStart.route(access: .full, photoCount: 3) == .grid(heading: "Your favorites"))
    #expect(PhotoStoryStart.route(access: .limited, photoCount: 2) == .grid(heading: "Photos you allowed"))
    #expect(PhotoStoryStart.route(access: .full, photoCount: 0) == .picker, "an empty Favorites album opens the picker")
    #expect(PhotoStoryStart.route(access: .limited, photoCount: 0) == .picker, "nothing allowed opens the picker")
    #expect(PhotoStoryStart.route(access: .none, photoCount: 5) == .picker, "no access opens the picker and asks nothing")
}

@Test func swipeToDismissIsOffWhileThePickerShows() {
    #expect(!PhotoStoryStart.allowsSwipeToDismiss(start: .picker, showsAllPhotos: false), "the inline picker takes the downward swipe")
    #expect(!PhotoStoryStart.allowsSwipeToDismiss(start: .grid(heading: "Your favorites"), showsAllPhotos: true), "All photos pushes the picker")
    #expect(PhotoStoryStart.allowsSwipeToDismiss(start: .grid(heading: "Your favorites"), showsAllPhotos: false), "the grid keeps the swipe")
    #expect(PhotoStoryStart.allowsSwipeToDismiss(start: .explain, showsAllPhotos: false))
    #expect(PhotoStoryStart.allowsSwipeToDismiss(start: nil, showsAllPhotos: false), "the sheet can close while the access loads")
}
