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
