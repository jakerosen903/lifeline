import Foundation
import Testing
@testable import LifelineKit

private let d = CivilDate(year: 2019, month: 7, day: 14)!

private func m(_ n: Int) -> [Memory] {
    (0..<n).map { i in
        Memory(id: .init(), title: "M\(i)", summaryQuote: "M\(i)", visibility: .timeline, chapterID: nil, createdFromCandidateID: .init(), createdAt: .now)
    }
}
private func offer(_ memories: [Memory]) -> PhotoStoryCard.StoryDateOffer? { memories.isEmpty ? nil : .init(date: d, memories: memories) }
private func change(_ memory: Memory) -> PhotoDateChange { PhotoDateChange(memory: memory.id, before: .unplaced, date: d) }
private func offerPart(_ text: String, _ button: String, _ memories: [Memory], canUndo: Bool) -> PhotoDatePart {
    .offer(.init(text: text, button: button, date: d, memories: memories, canUndo: canUndo))
}

@Test func theDatePart() {
    let day = "The photo is dated 14 July 2019."
    // No offer, nothing done.
    #expect(PhotoDatePart.state(offer: nil, holdingCount: 2, used: [], seen: []) == .hidden)
    // Before a tap.
    let a = m(14)
    #expect(PhotoDatePart.state(offer: offer(Array(a[..<1])), holdingCount: 2, used: [], seen: [])
            == offerPart("\(day) One moment has no date you said.", "Use for that one", Array(a[..<1]), canUndo: false))
    #expect(PhotoDatePart.state(offer: offer(Array(a[..<2])), holdingCount: 3, used: [], seen: [])
            == offerPart("\(day) Two moments have no date you said.", "Use for those 2", Array(a[..<2]), canUndo: false))
    #expect(PhotoDatePart.state(offer: offer(Array(a[..<3])), holdingCount: 3, used: [], seen: [])
            == offerPart("\(day) Three moments have no date you said.", "Use for all 3", Array(a[..<3]), canUndo: false))
    #expect(PhotoDatePart.state(offer: offer(Array(a[..<1])), holdingCount: 1, used: [], seen: [])
            == offerPart("\(day) One moment has no date you said.", "Use for that one", Array(a[..<1]), canUndo: false))
    #expect(PhotoDatePart.state(offer: offer(Array(a[..<12])), holdingCount: 13, used: [], seen: [])
            == offerPart("\(day) Twelve moments have no date you said.", "Use for those 12", Array(a[..<12]), canUndo: false))
    #expect(PhotoDatePart.state(offer: offer(Array(a[..<13])), holdingCount: 14, used: [], seen: [])
            == offerPart("\(day) 13 moments have no date you said.", "Use for those 13", Array(a[..<13]), canUndo: false))
    // After a tap: the counts are what the tap changed.
    let b = m(3)
    let two = Array(b[..<2])
    #expect(PhotoDatePart.state(offer: nil, holdingCount: 3, used: two.map(change), seen: Set(two.map(\.id)))
            == .used(text: "\(day) Two moments now use that date.", button: "Used for those 2"))
    let one = Array(b[..<1])
    #expect(PhotoDatePart.state(offer: nil, holdingCount: 1, used: one.map(change), seen: Set(one.map(\.id)))
            == .used(text: "\(day) One moment now uses that date.", button: "Used for that one"))
    // After a tap, a memory kept later: the offer is back, and Undo stays.
    let c = Array(b[2...])
    #expect(PhotoDatePart.state(offer: offer(c), holdingCount: 3, used: two.map(change), seen: Set(two.map(\.id)))
            == offerPart("\(day) One moment has no date you said.", "Use for that one", c, canUndo: true))
    // After a tap, one memory left unchecked: it was offered at the tap, so it does not bring the offer back.
    let pair = Array(b[..<2])
    #expect(PhotoDatePart.state(offer: offer([pair[1]]), holdingCount: 2, used: [change(pair[0])], seen: Set(pair.map(\.id)))
            == .used(text: "\(day) One moment now uses that date.", button: "Used for that one"))
    // After a tap, the store moves on (a memory now has a said date): the counts do not follow it.
    #expect(PhotoDatePart.state(offer: nil, holdingCount: 2, used: pair.map(change), seen: Set(pair.map(\.id)))
            == .used(text: "\(day) Two moments now use that date.", button: "Used for those 2"))
}

@Test func theOfferCarriesItsMemoriesAndDate() {
    let all = m(3)
    let part = PhotoDatePart.state(offer: offer(all), holdingCount: 3, used: [change(all[0])], seen: [all[0].id])
    guard case .offer(let o) = part else { Issue.record("expected an offer"); return }
    #expect(o.memories == [all[1], all[2]], "the open ones, in order")
    #expect(o.date == d)
}

@Test func chooseButton() {
    #expect(PhotoDatePart.chooseButton(count: 1) == "Use for 1")
    #expect(PhotoDatePart.chooseButton(count: 3) == "Use for 3")
}
