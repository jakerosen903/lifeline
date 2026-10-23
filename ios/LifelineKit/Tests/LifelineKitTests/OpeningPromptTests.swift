import Foundation
import Testing
@testable import LifelineKit

private func item(_ text: String, payoff: Int) -> CuriosityItem {
    CuriosityItem(id: .init(), kind: .unresolvedAnchor, text: text, payoffCount: payoff, status: .open, sourceMemoryID: nil, targetMemoryID: nil)
}
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func bankLoadsWithHouseFirstAndNoDuplicateIDs() throws {
    let bank = try PromptBank.load()
    #expect(bank.count >= 36)
    #expect(bank.first?.id == "house" && bank.first?.text == "Tell me about the house you grew up in.")
    #expect(Set(bank.map(\.id)).count == bank.count)
    #expect(bank.allSatisfy { !$0.text.isEmpty && $0.text.hasSuffix(".") || $0.text.hasSuffix("?") })
    #expect(!bank.contains { $0.text.lowercased().contains("what year") || $0.text.lowercased().contains("when were you born") }, "never a date question")
}

@Test func firstSessionOpensWithTheHouse() throws {
    let bank = try PromptBank.load()
    let opening = OpeningChooser.choose(curiosity: [], bank: bank, lastUsed: [:], now: now)
    #expect(opening.main.logID == "house")
    #expect(opening.alternates.map(\.logID) == bank[1...3].map(\.id))
}

@Test func usedPromptsRotateUntilTheBankIsExhausted() throws {
    let bank = try PromptBank.load()
    let afterOne = OpeningChooser.choose(curiosity: [], bank: bank, lastUsed: ["house": now], now: now)
    #expect(afterOne.main.logID == bank[1].id)
    var used: [String: Date] = [:]
    for (i, prompt) in bank.enumerated() { used[prompt.id] = now.addingTimeInterval(Double(i) * 86_400) }
    let exhausted = OpeningChooser.choose(curiosity: [], bank: bank, lastUsed: used, now: now.addingTimeInterval(1_000 * 86_400))
    #expect(exhausted.main.logID == "house", "the least recently used comes back first")
}

@Test func openCuriosityItemLeads() throws {
    let bank = try PromptBank.load()
    let graduation = item("graduation", payoff: 2), move = item("the move", payoff: 1)
    let opening = OpeningChooser.choose(curiosity: [move, graduation], bank: bank, lastUsed: [:], now: now)
    guard case .curiosity(let chosen, let text) = opening.main else { Issue.record("expected a curiosity opener, got \(opening.main)"); return }
    #expect(chosen.id == graduation.id && text == "You mentioned “graduation”. Tell me about that.")
    #expect(opening.main.logID == "curiosity:\(graduation.id.rawValue)")
    #expect(opening.alternates.count == 3 && opening.alternates.allSatisfy { if case .scene = $0 { true } else { false } })
}

@Test func aCuriosityItemUsedThisWeekIsSkipped() throws {
    let bank = try PromptBank.load()
    let graduation = item("graduation", payoff: 2)
    let recent = OpeningChooser.choose(curiosity: [graduation], bank: bank, lastUsed: ["curiosity:\(graduation.id.rawValue)": now.addingTimeInterval(-3 * 86_400)], now: now)
    #expect(recent.main.logID == "house")
    let stale = OpeningChooser.choose(curiosity: [graduation], bank: bank, lastUsed: ["curiosity:\(graduation.id.rawValue)": now.addingTimeInterval(-8 * 86_400)], now: now)
    #expect(stale.main.logID == "curiosity:\(graduation.id.rawValue)")
}

@Test func alternatesNeverRepeatTheMain() throws {
    let bank = try PromptBank.load()
    for used in [[:], ["house": now], ["house": now, bank[1].id: now]] {
        let opening = OpeningChooser.choose(curiosity: [], bank: bank, lastUsed: used, now: now)
        #expect(!opening.alternates.map(\.logID).contains(opening.main.logID))
        #expect(Set(opening.alternates.map(\.logID)).count == 3)
    }
}

@Test func promptLogRecordsTheLatestUse() throws {
    let db = try AppDatabase.inMemory()
    let sessions = SessionRepository(db)
    let log = PromptLogRepository(db)
    let (a, _) = try StoreFixtures.session(in: sessions)
    let (b, _) = try StoreFixtures.session(in: sessions)
    try log.record(promptID: "house", session: a, at: now)
    try log.record(promptID: "house", session: b, at: now.addingTimeInterval(60))
    try log.record(promptID: "meal", session: b, at: now)
    let used = try log.lastUsed()
    #expect(used["house"] == now.addingTimeInterval(60) && used["meal"] == now)
}
