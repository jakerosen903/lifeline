import Testing
@testable import LifelineKit

// M6 / R29: "Done" on a kept link. The same person settles when any link in the chosen scope is still open.
@Test func doneDecidesFromEveryLinkInTheScope() {
    let table: [(keepsPerson: Bool, scope: [LinkOrigin?], expected: WhoIsThisDone)] = [
        (false, [.confirmed], .move),
        (false, [], .move),
        (true, [.assumed], .settle),
        (true, [.new], .settle),
        (true, [.confirmed], .nothing),
        (true, [.said], .nothing),
        (true, [nil], .nothing),
        (true, [.confirmed, .assumed, .assumed], .settle),   // the tapped link is settled, the other moments are not
        (true, [nil, .new], .settle),
        (true, [.said, .confirmed, nil], .nothing),
        (true, [], .nothing),
    ]
    for row in table {
        #expect(WhoIsThisDone.decide(keepsPerson: row.keepsPerson, scope: row.scope) == row.expected, "\(row)")
    }
}
