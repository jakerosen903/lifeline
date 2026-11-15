import Foundation
import Testing
@testable import LifelineKit

@Test func theBarLabelNamesThePage() {
    let id = EntityID()
    #expect(SessionSubject.barLabel(nil) == "Tell a story")
    #expect(SessionSubject.barLabel(.init(entityID: id, title: "Maya", isOwner: false)) == "Tell a story about Maya")
    #expect(SessionSubject.barLabel(.init(entityID: id, title: "Jake", isOwner: true)) == "Tell a story about yourself")
}
