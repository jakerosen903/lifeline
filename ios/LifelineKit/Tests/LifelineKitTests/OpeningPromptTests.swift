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

// MARK: - A session about a subject

private func entityItem(_ text: String, entity: EntityID?, payoff: Int = 1, status: CuriosityStatus = .open) -> CuriosityItem {
    CuriosityItem(id: .init(), kind: .personWithoutMoment, text: text, payoffCount: payoff, status: status,
                  sourceMemoryID: nil, targetMemoryID: nil, entityID: entity)
}

@Test func aSubjectWithAnOpenSceneQuestionOpensWithIt() throws {
    let bank = try PromptBank.load()
    let maya = SessionSubject(entityID: .init(), title: "Maya", isOwner: false)
    let question = entityItem("Is there one time with Maya that stands out?", entity: maya.entityID)
    let other = entityItem("Is there one time with Sam that stands out?", entity: .init(), payoff: 9)
    let usedYesterday = ["curiosity:\(question.id.rawValue)": now.addingTimeInterval(-86_400)]
    let opening = OpeningChooser.choose(subject: maya, curiosity: [other, question], bank: bank, lastUsed: usedYesterday, now: now)
    #expect(opening.main == .curiosity(question, text: OpeningChooser.phrase(for: question)), "the cooldown does not apply, and another entity's question never leads")
}

@Test func aSubjectsDismissedOrAnsweredQuestionDoesNotLead() throws {
    let bank = try PromptBank.load()
    let maya = SessionSubject(entityID: .init(), title: "Maya", isOwner: false)
    let dismissed = entityItem("Is there one time with Maya that stands out?", entity: maya.entityID, status: .dismissed)
    let answered = entityItem("What was Maya like?", entity: maya.entityID, payoff: 5, status: .answered)
    let opening = OpeningChooser.choose(subject: maya, curiosity: [dismissed, answered], bank: bank, lastUsed: [:], now: now)
    #expect(opening.main == .subject(maya, text: "Tell me about Maya."))
}

@Test func aSubjectWithNoQuestionOpensWithItsTitle() throws {
    let bank = try PromptBank.load()
    let volvo = SessionSubject(entityID: .init(), title: "Dad's Volvo", isOwner: false)
    let opening = OpeningChooser.choose(subject: volvo, curiosity: [], bank: bank, lastUsed: [:], now: now)
    #expect(opening.main.text == "Tell me about Dad's Volvo.")
    #expect(opening.main.logID == "subject:\(volvo.entityID.rawValue)")
}

@Test func theOwnerAsSubjectOpensWithThemself() throws {
    let bank = try PromptBank.load()
    let owner = SessionSubject(entityID: .init(), title: "Ines", isOwner: true)
    let opening = OpeningChooser.choose(subject: owner, curiosity: [], bank: bank, lastUsed: [:], now: now)
    #expect(opening.main.text == "Tell me something about yourself.")
}

@Test func aSubjectKeepsTheSceneAlternates() throws {
    let bank = try PromptBank.load()
    let maya = SessionSubject(entityID: .init(), title: "Maya", isOwner: false)
    let opening = OpeningChooser.choose(subject: maya, curiosity: [], bank: bank, lastUsed: [:], now: now)
    #expect(opening.alternates == bank.prefix(3).map(OpeningPrompt.scene))
}

@Test func aSubjectsHigherPayoffQuestionLeads() throws {
    let bank = try PromptBank.load()
    let maya = SessionSubject(entityID: .init(), title: "Maya", isOwner: false)
    let small = entityItem("What was Maya like?", entity: maya.entityID, payoff: 1)
    let big = entityItem("Is there one time with Maya that stands out?", entity: maya.entityID, payoff: 4)
    let opening = OpeningChooser.choose(subject: maya, curiosity: [small, big], bank: bank, lastUsed: [:], now: now)
    #expect(opening.main == .curiosity(big, text: OpeningChooser.phrase(for: big)))
}

@Test func aSubjectExcludedFromAIDoesNotNameItselfInTheOpening() throws {
    let bank = try PromptBank.load()
    let secret = SessionSubject(entityID: .init(), title: "Maya", isOwner: false, excludedFromAI: true)
    let opening = OpeningChooser.choose(subject: secret, curiosity: [], bank: bank, lastUsed: [:], now: now)
    #expect(!opening.main.text.contains("Maya"))
    #expect(opening.main == OpeningChooser.choose(curiosity: [], bank: bank, lastUsed: [:], now: now).main, "the plain tab opening")
}

// MARK: - A session about a photo

@Test func aPhotoOpensWithTellMeAboutThisOne() throws {
    let bank = try PromptBank.load()
    let id = PhotoID()
    let openItem = item("graduation", payoff: 2)
    let opening = OpeningChooser.choose(photo: id, curiosity: [openItem], bank: bank, lastUsed: [:], now: now)
    #expect(opening.main == .photo(id, text: "Tell me about this one."))
    #expect(opening.main.logID == "photo")
    #expect(opening.alternates.count == 3)
    #expect(opening.alternates.allSatisfy { if case .scene = $0 { true } else { false } }, "no alternate is a curiosity item")
    #expect(opening.alternates.map(\.logID) == bank.prefix(3).map(\.id), "the first three scenes")
}

@Test func aPhotoWinsOverASubject() throws {
    let bank = try PromptBank.load()
    let maya = SessionSubject(entityID: EntityID(), title: "Maya", isOwner: false)
    let opening = OpeningChooser.choose(photo: PhotoID(), subject: maya, curiosity: [], bank: bank, lastUsed: [:], now: now)
    #expect(opening.main.logID == "photo")
}

// PB10: the opening goes to the interviewer's model, so a person from a contact is named by what the owner said.
@Test func aSubjectFromAContactOpensWithTheSaidNameOrPlainly() throws {
    let bank = try PromptBank.load()
    let robyn = SessionSubject(entityID: .init(), title: "Robyn Vale", isOwner: false, modelTitle: "Robyn")
    #expect(OpeningChooser.choose(subject: robyn, curiosity: [], bank: bank, lastUsed: [:], now: now).main.text == "Tell me about Robyn.")
    #expect(SessionSubject.barLabel(robyn) == "Tell a story about Robyn Vale", "the screen still shows the page's name")
    let unnamed = SessionSubject(entityID: .init(), title: "Robyn Vale", isOwner: false, modelTitle: nil)
    let opening = OpeningChooser.choose(subject: unnamed, curiosity: [], bank: bank, lastUsed: [:], now: now)
    #expect(!opening.main.text.contains("Vale"))
    #expect(opening.main == OpeningChooser.choose(curiosity: [], bank: bank, lastUsed: [:], now: now).main, "the plain tab opening")
}
