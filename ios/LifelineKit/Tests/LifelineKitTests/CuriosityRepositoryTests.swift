import Foundation
import Testing
@testable import LifelineKit

private struct Env {
    let store: ExtractionStore, repo: CuriosityRepository, segment: Segment
    init() throws {
        let db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        repo = CuriosityRepository(db)
        let (session, _) = try StoreFixtures.session(in: store.sessions)
        segment = try store.sessions.segments(in: session)[0]
    }
    func floating(_ title: String) throws -> MemoryID {
        try store.memories.insertFloating(title: title, segment: segment.id, startMs: 0, endMs: 500).id
    }
    func item(_ text: String, payoff: Int, target: MemoryID) -> CuriosityItem {
        CuriosityItem(id: .init(), kind: .unresolvedAnchor, text: text, payoffCount: payoff, status: .open, sourceMemoryID: nil, targetMemoryID: target)
    }
}

@Test func replaceOpenAnchorItemsClosesTheStaleOnes() throws {
    let env = try Env()
    let a = try env.floating("graduation"), b = try env.floating("the move")
    try env.repo.replaceOpenAnchorItems([env.item("graduation", payoff: 1, target: a), env.item("the move", payoff: 1, target: b)])
    #expect(try env.repo.open().count == 2)
    try env.repo.replaceOpenAnchorItems([env.item("graduation", payoff: 3, target: a)])
    let open = try env.repo.open()
    #expect(open.count == 1 && open[0].text == "graduation" && open[0].payoffCount == 3)
    #expect(try env.repo.item(forTarget: a)?.id == open[0].id)
    try env.repo.setStatus(open[0].id, .answered)
    #expect(try env.repo.open().isEmpty)
}

@Test func openItemsComeByPayoffThenText() throws {
    let env = try Env()
    try env.repo.replaceOpenAnchorItems([
        env.item("b", payoff: 1, target: try env.floating("b")),
        env.item("a", payoff: 1, target: try env.floating("a")),
        env.item("z", payoff: 4, target: try env.floating("z")),
    ])
    #expect(try env.repo.open().map(\.text) == ["z", "a", "b"])
}
