import Foundation
import Testing
@testable import LifelineKit

// PC-d Task 3: a memory card stores the people its handles name.

private func memory(handles: [String], peopleRefs: [String] = [], aboutRef: String? = nil) -> MemoryOut {
    MemoryOut(ref: "m1", kind: .event, title: "Two Robyns at the lake", quote: "Robyn and Robyn swam", segmentSpan: WordSpan(startWord: 0, endWord: 3),
              peopleRefs: peopleRefs, placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9,
              aboutRef: aboutRef, personHandles: handles)
}

private func validated(_ memory: MemoryOut, people: [PersonOut], mentions: [MentionOut] = []) -> OutputValidator.Validated {
    OutputValidator.Validated(accepted: [.memory(memory)] + mentions.map { .mention($0) }, rejected: [], flags: .none, people: people)
}

private func firstMemory(_ v: OutputValidator.Validated) -> MemoryOut? {
    for candidate in v.accepted { if case .memory(let m) = candidate { return m } }
    return nil
}

private let robynCousin = PersonOut(handle: "p1", saidName: "Robyn", relationText: "my cousin", personID: nil)
private let robynFriend = PersonOut(handle: "p2", saidName: "Robyn", relationText: "my friend", personID: nil)

@Test func aMemoryStoresThePeopleOfItsHandlesAndTheirSaidNames() throws {
    let out = HandleResolve.resolved(validated(memory(handles: ["p1", "p2"]), people: [robynCousin, robynFriend]), knownPeople: [])
    let m = try #require(firstMemory(out))
    #expect(m.handlePeople == [robynCousin, robynFriend])
    #expect(m.peopleRefs == ["Robyn", "Robyn"])
}

@Test func aHandleListedTwiceInOneMemoryIsOnePerson() throws {
    let out = HandleResolve.resolved(validated(memory(handles: ["p1", "p1"]), people: [robynCousin]), knownPeople: [])
    let m = try #require(firstMemory(out))
    #expect(m.handlePeople == [robynCousin] && m.peopleRefs == ["Robyn"])
}

// Review Focus 3: an id the packet did not hold is cleared, and so is the owner's (never in the packet).
@Test func aPersonIDThePacketDidNotHoldIsCleared() throws {
    let known = PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: "person-known")
    let unknown = PersonOut(handle: "p2", saidName: "Robyn", relationText: nil, personID: "person-invented")
    let owner = PersonOut(handle: "p3", saidName: "Robyn", relationText: nil, personID: "person-owner")
    let out = HandleResolve.resolved(validated(memory(handles: ["p1", "p2", "p3"]), people: [known, unknown, owner]), knownPeople: ["person-known"])
    let m = try #require(firstMemory(out))
    #expect(m.handlePeople.map(\.personID) == ["person-known", nil, nil])
    #expect(out.people.map(\.personID) == ["person-known", nil, nil])
}

@Test func aMemoryWithNoHandleIsNotChanged() {
    let input = validated(memory(handles: [], peopleRefs: ["Robyn"]), people: [robynCousin])
    #expect(HandleResolve.resolved(input, knownPeople: []) == input)
}

@Test func aV6OutputPassesThroughEveryStepUnchanged() {
    let mention = MentionOut(text: "Robyn", kind: .person, confidence: 0.8, ref: "x1")
    let input = OutputValidator.Validated(accepted: [.memory(memory(handles: [], peopleRefs: ["Robyn"], aboutRef: "x1")), .mention(mention)], rejected: [], flags: .none)
    let owner = OwnerNames(names: ["Dana"])
    var out = owner.removingOwner(from: input)
    out = AboutRefCheck.cleared(out, knownIDs: [])
    out = HandleResolve.resolved(out, knownPeople: [])
    #expect(out == input)
}

@Test func theOwnerAsAPersonIsDroppedAndTheMemoryStays() throws {
    let ownerEntry = PersonOut(handle: "p1", saidName: "Dana", relationText: nil, personID: nil)
    let input = validated(memory(handles: ["p1", "p2"], peopleRefs: ["Dana", "Robyn"]), people: [ownerEntry, robynFriend])
    let out = HandleResolve.resolved(OwnerNames(names: ["Dana"]).removingOwner(from: input), knownPeople: [])
    #expect(out.people == [robynFriend])
    let m = try #require(firstMemory(out))
    #expect(m.personHandles == ["p2"])
    #expect(m.handlePeople == [robynFriend] && m.peopleRefs == ["Robyn"])
}

@Test func aNameSaidWithARelationIsNotTheOwner() {
    let cousin = PersonOut(handle: "p1", saidName: "Dana", relationText: "my cousin", personID: nil)
    let input = validated(memory(handles: ["p1"]), people: [cousin])
    #expect(OwnerNames(names: ["Dana"]).removingOwner(from: input).people == [cousin])
}

@Test func anAboutRefThatIsAHandleOfThisOutputSurvives() throws {
    let input = validated(memory(handles: ["p1"], aboutRef: "p1"), people: [robynCousin])
    let m = try #require(firstMemory(AboutRefCheck.cleared(input, knownIDs: [])))
    #expect(m.aboutRef == "p1")
}

@Test func anAboutRefThatNamesNoHandleIsCleared() throws {
    let input = validated(memory(handles: ["p1"], aboutRef: "p9"), people: [robynCousin])
    let m = try #require(firstMemory(AboutRefCheck.cleared(input, knownIDs: [])))
    #expect(m.aboutRef == nil)
}

@Test func aPersonMentionWithAHandleTheMemoryCarriesIsCarried() {
    // The text differs from the said name; the handle alone ties them.
    let m = memory(handles: ["p1"], peopleRefs: ["Robyn"])
    #expect(CarriedName.carries(m, MentionOut(text: "my cousin", kind: .person, confidence: 0.8, handle: "p1")))
    #expect(!CarriedName.carries(m, MentionOut(text: "my friend", kind: .person, confidence: 0.8, handle: "p2")))
}

@Test func aMentionWithAnUnknownHandleIsReadAsHavingNone() {
    // No `people` entry has "p9": the text rule still decides.
    let m = memory(handles: ["p1"], peopleRefs: ["Robyn"])
    #expect(CarriedName.carries(m, MentionOut(text: "Robyn", kind: .person, confidence: 0.8, handle: "p9")))
    #expect(!CarriedName.carries(m, MentionOut(text: "Theo", kind: .person, confidence: 0.8, handle: "p9")))
}

@Test func aMentionTiedToTheOwnersHandleIsDroppedAndAFactAboutItIsAboutSelf() throws {
    let ownerEntry = PersonOut(handle: "p1", saidName: "Dana", relationText: nil, personID: nil)
    let me = MentionOut(text: "me", kind: .person, confidence: 0.8, handle: "p1")
    let input = validated(memory(handles: ["p1"], aboutRef: "p1"), people: [ownerEntry], mentions: [me])
    let out = OwnerNames(names: ["Dana"]).removingOwner(from: input)
    #expect(out.accepted.count == 1, "only the memory stays")
    #expect(try #require(firstMemory(out)).aboutRef == "self")
}

// PC-d Task 4b (D17): a handle of the recording so far, with no `people` entry in this output.
private let recordingRobyn = ContextPacket.RecordingPerson(handle: "p1", saidNames: ["Robyn", "my roommate"], relation: "from work", personID: "person-robyn")

@Test func aRecordingHandleWithNoEntryStoresTheRecordingsFirstSaidName() throws {
    let out = HandleResolve.resolved(validated(memory(handles: ["p1"]), people: []), knownPeople: ["person-robyn"], recording: [recordingRobyn])
    let m = try #require(firstMemory(out))
    #expect(m.handlePeople == [PersonOut(handle: "p1", saidName: "Robyn", relationText: "from work", personID: "person-robyn")])
    #expect(m.peopleRefs == ["Robyn"])
    #expect(out.people.isEmpty, "the output's own people are not changed")
}

@Test func aRecordingHandlesPersonIDThePacketDidNotHoldIsCleared() throws {
    let out = HandleResolve.resolved(validated(memory(handles: ["p1"]), people: []), knownPeople: [], recording: [recordingRobyn])
    #expect(try #require(firstMemory(out)).handlePeople.map(\.personID) == [nil])
}

@Test func anOwnEntryForARecordingHandleWins() throws {
    let again = PersonOut(handle: "p1", saidName: "Rob", relationText: nil, personID: nil)
    let out = HandleResolve.resolved(validated(memory(handles: ["p1"]), people: [again]), knownPeople: [], recording: [recordingRobyn])
    let m = try #require(firstMemory(out))
    #expect(m.handlePeople == [again] && m.peopleRefs == ["Rob"])
}

@Test func aV6OutputPassesThroughWithARecordingUnchanged() {
    let input = OutputValidator.Validated(accepted: [.memory(memory(handles: [], peopleRefs: ["Robyn"]))], rejected: [], flags: .none)
    let out = HandleResolve.resolved(AboutRefCheck.cleared(input, knownIDs: [], recordingHandles: ["p1"]), knownPeople: [], recording: [recordingRobyn])
    #expect(out == input)
}

@Test func anAboutRefThatOnlyTheRecordingHoldsSurvives() throws {
    let input = validated(memory(handles: [], aboutRef: "p1"), people: [])
    #expect(try #require(firstMemory(AboutRefCheck.cleared(input, knownIDs: [], recordingHandles: ["p1"]))).aboutRef == "p1")
}

@Test func anAboutRefKnownNowhereIsClearedAndTheMemoryStays() throws {
    let input = validated(memory(handles: [], aboutRef: "p9"), people: [])
    let out = AboutRefCheck.cleared(input, knownIDs: [], recordingHandles: ["p1"])
    #expect(out.accepted.count == 1)
    #expect(try #require(firstMemory(out)).aboutRef == nil)
}

// D22: a handle in `about_ref` is one of the memory's people.
@Test func aFactAboutARecordingHandleWithNoPersonHandlesStoresThatPerson() throws {
    let out = HandleResolve.resolved(validated(memory(handles: [], aboutRef: "p1"), people: []), knownPeople: ["person-robyn"], recording: [recordingRobyn])
    let m = try #require(firstMemory(out))
    #expect(m.personHandles == ["p1"])
    #expect(m.handlePeople == [PersonOut(handle: "p1", saidName: "Robyn", relationText: "from work", personID: "person-robyn")])
    #expect(m.peopleRefs == ["Robyn"])
}

@Test func anAboutRefHandleOfThisOutputIsAddedAtTheEnd() throws {
    let out = HandleResolve.resolved(validated(memory(handles: ["p2"], aboutRef: "p1"), people: [robynCousin, robynFriend]), knownPeople: [])
    let m = try #require(firstMemory(out))
    #expect(m.personHandles == ["p2", "p1"])
    #expect(m.handlePeople == [robynFriend, robynCousin])
}

@Test func anAboutRefHandleTheMemoryListsIsNotAddedAgain() throws {
    let out = HandleResolve.resolved(validated(memory(handles: ["p1"], aboutRef: "p1"), people: [robynCousin]), knownPeople: [])
    #expect(try #require(firstMemory(out)).personHandles == ["p1"])
}

@Test func anAboutRefThatIsNotAHandleChangesNothing() throws {
    for about in ["self", "t1", "entity-lake"] {
        let input = validated(memory(handles: ["p1"], aboutRef: about), people: [robynCousin])
        let m = try #require(firstMemory(HandleResolve.resolved(input, knownPeople: [], recording: [recordingRobyn])))
        #expect(m.personHandles == ["p1"] && m.handlePeople == [robynCousin], "about_ref \(about)")
    }
    let noHandles = validated(memory(handles: [], aboutRef: "t1"), people: [])
    #expect(HandleResolve.resolved(noHandles, knownPeople: [], recording: [recordingRobyn]) == noHandles)
}
