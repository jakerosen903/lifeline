# Photo Card and Key Photo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The photo card keeps one layout before and after a choice: one moments row, the pages as chips in groups that a tap adds and a second tap takes off, and one date offer for the story with Undo. On a page, the first photo is the key photo, and the person changes it with a drag on the shelf, a button in the viewer or a VoiceOver action.

**Architecture:** Task 1 adds the write that changes several memory ranges at once, and the reader's `useDate` and `undoDate` on top of it. Task 2 adds the new shape of the card (page groups with a chosen flag, one date offer) and the pure rules of the date part, beside the old fields, so the app still builds. Task 3 adds `reorder` and makes `setCover` a move to the front. Task 4 builds the card view on the new shape and removes the old fields. Task 5 adds the drag on the shelf, the viewer button, the VoiceOver action and the words "key photo". Task 6 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, GRDB 7 (no migration), Swift Testing, XCUITest.

**Spec:** `docs/specs/2026-11-18-photo-card-key-photo.md`. Read it whole before Task 1. It builds on `docs/specs/2026-11-16-photo-story.md` and `docs/plans/2026-11-16-photo-story.md`. Screens: `docs/design/PH1_PhotoCard.dc.html`, `PH2_PhotoCardAfter.dc.html`, `KP1_KeyPhoto.dc.html`.

**Worktree and branch:** `/Users/jakerosen/dev/lifeline/lifeline-photo-card`, branch `photo-card`, cut from `photo-story` at `6972f88`. Work only there.

## Decisions made in this plan

Each decision names its cost if it is wrong.

1. **The old card fields stay until Task 4.** Task 2 adds `pageGroups` and `dateOffer` beside `pageOffers`, `dateOffers` and `ownerEntity`. Task 4 removes the three old fields in the commit that stops using them. Every commit builds and every commit is green. Cost: Task 2 carries two shapes for two tasks.
2. **Undo is as good as the resolver.** `undoDate` writes the old ranges back and then runs the resolver, as the spec says. The resolver sets every `inferred` range to unplaced and computes it again from the anchors. A guess that has an anchor comes back the same. A guess that has no anchor does not come back: it becomes unplaced. Such a range exists only where code wrote `inferred` with no anchor (the seed `writeSpine` does); no resolver run keeps it. Task 1 pins both results. Cost: if the owner wants that guess back, `undoDate` must skip the resolver for it, and the next resolver run erases it anyway.
3. **Undo lives in the card's view model.** The landing and the session's page own that view model. Undo stays while that screen is in the navigation stack, also after the person opens a memory page and comes back. It goes when the screen closes. Cost: one `@State` move if the owner wants Undo to go on the first push.
4. **A second tap adds to the first.** When a new memory is kept after a tap and the person taps again, the card keeps the old ranges of both taps. "Undo" puts back both. The count after the tap is the total. Cost: one array becomes a stack of arrays.
5. **A memory that the person left unchecked does not bring the offer back.** The card remembers the memories that it offered at the tap. Only a memory that was not offered then (it was kept later) shows the state before the tap again. Cost: the unchecked memory gets no second offer until the screen opens again; the memory page can still set its date.
6. **The count in the sentence is a word from one to twelve** ("One", "Two", … "Twelve"), then digits. The button always has digits. PH1 shows "Three moments" and "Use for those 3". Cost: one pure function.
7. **Copy that the spec does not give.** After the tap, for one memory: "One moment now uses that date." and "Used for that one". The sheet's titles are the row's own text ("On {n} moments from this story") and "Choose moments"; its close button is "Done". Error lines: "Could not take the photo off this page", "Could not undo the date", "Could not change the order of the photos", "Could not make this the key photo". Cost: string changes.
8. **"Choose moments" shows for one memory too.** The spec lists the link with no condition, and the link's row keeps the layout of the two states equal. Cost: a sheet with one checkbox.
9. **While a moment waits, the row shows only the waiting sentence.** The spec gives the row three states, and the first one does not open. So the person cannot reach "Remove" for a kept memory until every moment of the session is sorted. Cost: the row needs a fourth state.
10. **A chip keeps its size in both states.** The space for the tick is in the chip when it is not chosen. This is how "only the state of a control changes" holds for a row of chips. Cost: a slightly wider outline chip.
11. **The label "Key photo" is a small pill on the first tile, with its own filled background.** KP1 draws it there. The S4 rule "no text on a photo" still holds for the page header. Cost: move the label under the tile.
12. **The drag is a custom gesture** (a long press, then a drag) on the tile, not the system drag and drop. A test can drive it with `press(forDuration:thenDragTo:)`, and a tap stays a plain button tap. Cost: no system lift animation.
13. **The kit owns the new order.** `PhotoOrder.moving(_:to:in:)` returns nil when nothing moves, so "a drag that ends where it started" writes nothing. The view never builds an order.
14. **The VoiceOver action is not asserted by a UI test.** XCUITest has no public way to list custom actions. The action calls the same shelf method as the drag, which tests cover. The device check covers its presence and its name. Cost: a regression in the action's name shows only on a device.
15. **A new seed flag, not a changed seed.** `-uiTesting-photoStoryGuess` adds one memory to the first seeded story. Without the flag the seed is as it was, so tests that count two memories keep their fixtures. The shelf tests use `-uiTesting-seedPhotos`, where Maya already has two photos. Cost: one more launch argument.
16. **Identifiers.** The spec names none. This plan sets them (see Global Constraints). `photoCard.useDate` moves from the offer block to the button. `photoCard.addToPage` is retired.

## Global Constraints

- No migration. No new network host. Nothing here sends a photo, a date or a title anywhere.
- A tap must not replace a date that the person said or confirmed. A date change from the card must have Undo on the same screen. The screen after a choice must have the same layout as the screen before it.
- The card suggests no person and no place that the memories do not name. An offer has no "No" and stores no "declined" state.
- The code keeps its names (`PhotoRole.cover`, `setCover`, `makeCover`, `photo.makeCover`). The person reads "key photo".
- Copy, exact:
  - Moments row: "This photo goes on each moment you keep." "On 1 moment from this story" "On {n} moments from this story". Sheet line button: "Remove", with the accessibility label "Remove from {title}".
  - Pages: "Also show this photo on" "Tap to add. Tap again to take it off." Group names: "People", "Places", "Things", "Ideas". The owner's chip: "You". Accessibility values: "added", "not added".
  - Date, before: "When did this happen?" "The photo is dated {d MMMM yyyy}. {N} moments have no date you said." "The photo is dated {d MMMM yyyy}. One moment has no date you said." "Use for those {n}" "Use for that one" "Use for all {n}" "Choose moments". Sheet button: "Use for {n}".
  - Date, after: "The photo is dated {d MMMM yyyy}. {N} moments now use that date." "Used for those {n}" "Undo". For one, decision 7.
  - "Remove the photo from this story" (no change).
  - Shelf: "The first photo is the key photo. Hold a photo and drag it to the front to change it." Tile label: "Key photo". Viewer: "Make this the key photo". VoiceOver action: "Move to front".
  - Memory page mark: "from a photo" (no change).
- Accessibility identifiers. Kept: `photoCard`, `photoCard.pending`, `photoCard.memory`, `photoCard.removeFromMemory`, `photoCard.removeFromStory`, `photoCard.confirmRemoveFromStory`, `photo.thumb`, `photo.header`, `photo.caption`, `photo.viewer`, `photo.makeCover`. Changed: `photoCard.useDate` is now the button. Retired: `photoCard.addToPage`. New: `photoCard.moments`, `photoCard.momentsSheet`, `photoCard.momentsDone`, `photoCard.group`, `photoCard.page`, `photoCard.date`, `photoCard.dateText`, `photoCard.dateUsed`, `photoCard.chooseMoments`, `photoCard.chooseMoment`, `photoCard.useChosen`, `photoCard.undoDate`, `photo.shelfHint`, `photo.keyLabel`.
- UI tests read state from accessibility values and labels, never from a colour.
- Every control is at least 44 by 44 points. Dynamic Type must not clip. A chip wraps to two lines and then cuts with an ellipsis. Colours come from `Theme`; no new colour value.
- View models do no reads in `init` and expose `isLoaded`. The views hold no rule: each sentence and each order comes from the kit.
- Kit tests: `cd ios/LifelineKit && swift test`, in full at every task.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'platform=iOS Simulator,id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`. Run `xcodegen generate` when a task adds a file. Each task names its classes. The report gives the verbatim `Executed N tests, with M failures` line for each. The whole UI suite runs once, by the controller, after the final review.
- The guards run before the PR: `python3 .github/scripts/pr_guards.py origin/main`.
- Real TDD: each new test is seen failing first. The tests that this plan changes are named in their task, each with its exact change. No other assertion is made weaker.
- Test photos come from `GeneratedPhoto`. Fixtures are invented (Maya, Dad, "The beach", "The picnic"). Never a real person's data.
- `ios/Config/Local.xcconfig` is never committed. Commit messages are imperative, one line, with a body when the why is not obvious. No AI attribution lines. Nothing is pushed.
- Docs under `docs/` use ASD-STE100 style.

## Review Focus

1. **Undo after the resolver ran.** The tap runs the resolver, and Undo runs it again. A guess with an anchor must come back equal. A guess with no anchor becomes unplaced (decision 2). A memory placed relative to the changed one must be placed again as before. Task 1 (`undoGivesAGuessWithAnAnchorItsDateBack`, `undoOfAGuessWithNoAnchorLeavesItUnplaced`, `undoPlacesAgainAMemoryThatPointedAtTheChangedOne`).
2. **A memory that changes between the tap and Undo.** The person says a date on the memory page, or the memory is deleted, or the photo leaves it. Undo must skip the first two, restore the third, and restore every other memory in one write. Task 1 (`undoDateSkipsAMemoryThatChangedAfterTheTap`, `updateRangesSkipsAMemoryThatIsGone`, `undoDateStillWorksAfterThePhotoLeftTheMemory`).
3. **An old shelf, and the one-cover index.** A page from before this plan can hold a cover that is not first in `sort_order`, and rows with equal `sort_order` after a fold. The first change must write 0, 1, 2 with the cover first, and must never hold two covers inside the write. Task 3 (`aShelfWhoseCoverIsNotFirstIsRepairedByTheNextChange`, `reorderMovesTheCoverWithoutBreakingTheIndex`, `reorderIgnoresWhatThePageDoesNotHoldAndKeepsWhatWasLeftOut`).
4. **A page that holds the photo and that no kept memory names.** It must show as a chosen chip, unless it is hidden. A photo taken off a page and put back must come back last, not as the key photo. Task 2 (`aPageThatHoldsThePhotoAndNoMemoryNamesIsListedChosen`, `aHiddenPageThatHoldsThePhotoIsNotListed`), Task 3 (`aPhotoPutBackOnAPageComesBackLast`).
5. **The date part after a tap.** A memory kept later shows the offer again with Undo still there; an unchecked memory does not; the counts after the tap do not follow the store. Task 2 (`theDatePart`, the rows marked "after a tap").

---

### Task 1: Several ranges in one write, and Undo (kit)

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/MemoryRepository.swift`, `Photos/PhotoStoryReader.swift`; `ios/Lifeline/Screens/Photos/PhotoCardViewModel.swift` (one call, so the app builds)
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoDateChange.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/PhotoStoryTests.swift`, `ResolverRunnerTests.swift`

**Interfaces:**
- Consumes: `MemoryRepository.refreshChapterRange(ofMemory:in:)` (static, exists), `TimeRange.fromPhoto(_:)`, `ResolverRunner(store:).run()`.
- Produces:
```swift
extension MemoryRepository {
    public struct RangeChange: Sendable, Equatable {
        public var memory: MemoryID
        public var range: TimeRange
        public var ifCurrently: TimeRange
        public init(memory: MemoryID, range: TimeRange, ifCurrently: TimeRange)
    }
    /// One write. Each change happens only while the stored range equals `ifCurrently`, and refreshes that memory's chapter.
    /// Returns the memories it changed, in the order given. A memory that is gone is skipped.
    @discardableResult
    public func updateRanges(_ changes: [RangeChange]) throws -> [MemoryID]
}

/// What "Undo" needs for one memory: the range before the tap, and the day the tap wrote.
public struct PhotoDateChange: Sendable, Equatable {
    public var memory: MemoryID
    public var before: TimeRange
    public var date: CivilDate
    public init(memory: MemoryID, before: TimeRange, date: CivilDate)
}

extension PhotoStoryReader {
    /// Sets each memory to `.fromPhoto(date)` in one write, checked against the range each `Memory` value carries.
    /// Runs the resolver one time when a memory changed. Returns one change for each memory it wrote.
    public func useDate(_ date: CivilDate, for memories: [Memory]) throws -> [PhotoDateChange]
    /// Puts back each `before` in one write, only where the stored range is still `.fromPhoto(change.date)`.
    /// Runs the resolver one time when a memory changed. Returns the memories it put back.
    @discardableResult
    public func undoDate(_ changes: [PhotoDateChange]) throws -> [MemoryID]
}
```
`PhotoStoryReader.useDate(_ offer: PhotoStoryCard.DateOffer)` is removed. `updateRange(_:_:ifCurrently:refreshingChapter:)` stays; other callers use it.

**Existing tests that change (call form only; every assertion stays):** `theReaderOffersTheNamedPagesAndTheDateAndAppliesTaps`, `usingTheDateMovesTheMemorysChapterWithIt`, `usingTheDateRePlacesAMemoryThatPointsAtIt`, `aStatedDateReplacesAPhotoDate` (all in `PhotoStoryTests.swift`) and `theResolverLeavesAPhotoDateAlone` (`ResolverRunnerTests.swift`): `reader.useDate(offer)` becomes `reader.useDate(offer.date, for: [offer.memory])`, or `reader.useDate(day, for: [memory])` where the test built the offer by hand. `usingTheDateSkipsAMemoryWhoseRangeChangedSinceTheCard` changes the same way and gains `#expect(changes.isEmpty)`.

- [ ] **Step 1: Write the failing tests.**

`PhotoStoryTests.swift` (uses `StoryFixture`, `WriteCounter` and `day` of that file; `d = day(2019, 7, 14)`). A test reads each memory from the store before it builds a change, as the card does.
```swift
@Test func updateRangesChangesSeveralMemoriesInOneWrite() throws
// a, b kept from pendingCard(ordinal: 0) and pendingCard(title: "The beach", ordinal: 1); chapter "Summers" contains a; trace on.
// let changed = try f.store.memories.updateRanges([.init(memory: a.id, range: .fromPhoto(d), ifCurrently: a.range),
//                                                  .init(memory: b.id, range: .fromPhoto(d), ifCurrently: b.range)])
// #expect(changed == [a.id, b.id]); #expect(counter.count == 1)
// #expect(fetch(a).range == .fromPhoto(d) && fetch(b).range == .fromPhoto(d)); #expect(chapter.range.earliest == d)
@Test func updateRangesSkipsAMemoryWhoseRangeChanged() throws
// b is set to TimeRange.year(2012, origin: .stated, evidence: "in 2012") after the changes are built.
// #expect(changed == [a.id]); #expect(fetch(b).range == said)
@Test func updateRangesSkipsAMemoryThatIsGone() throws           // delete b; #expect(changed == [a.id]); no throw
@Test func updateRangesWithNothingWritesNothing() throws         // #expect(try updateRanges([]) == []); #expect(counter.count == 0)
@Test func useDateReturnsTheOldRangeOfEachMemoryItChanged() throws
// a unplaced; b stated 2012 in the store, but passed with its older unplaced value.
// #expect(try f.reader.useDate(d, for: [a, staleB]) == [PhotoDateChange(memory: a.id, before: .unplaced, date: d)])
@Test func undoDatePutsBackEachRange() throws
// a unplaced, b unplaced; changes = useDate(d, for: [a, b]); #expect(try f.reader.undoDate(changes) == [a.id, b.id]); both .unplaced
@Test func undoDateSkipsAMemoryThatChangedAfterTheTap() throws
// between: try CandidateActions(store: f.store).setStatedRange(a.id, .stated(year: 2018))
// #expect(try f.reader.undoDate(changes) == [b.id]); #expect(fetch(a).range == .stated(year: 2018)); #expect(fetch(b).range == .unplaced)
@Test func undoDateStillWorksAfterThePhotoLeftTheMemory() throws
// between: _ = try f.store.photos.unlink(f.subject.id, from: .memory(a.id)); undo returns [a.id]; fetch(a).range == .unplaced
@Test func undoDateMovesTheChapterBack() throws                  // chapter "Summers" contains a: earliest == d after the tap, nil after Undo
```
`undoDate` puts the ranges back through `updateRanges`, so `updateRangesChangesSeveralMemoriesInOneWrite` is also the proof that Undo is one write.

`ResolverRunnerTests.swift` (uses `Env`):
```swift
@Test func undoGivesAGuessWithAnAnchorItsDateBack() throws
// try env.birthday("1986-05-10"); accept "The blue door" with the age anchor "I was six"; before = fetch (origin .inferred, earliest 1992-05-10)
// let inBand = CivilDate(iso: "1992-08-01")!                    // inside the guessed band: the tap is still allowed
// let changes = try reader.useDate(inBand, for: [before]); #expect(fetch.range == .fromPhoto(inBand))
// try reader.undoDate(changes); #expect(fetch.range == before.range); #expect(anchors(of:).allSatisfy(\.resolved))
@Test func undoOfAGuessWithNoAnchorLeavesItUnplaced() throws
// accept with no anchor; try env.store.memories.updateRange(id, .year(1999, origin: .inferred, evidence: nil)); before = fetch
// changes = useDate(photoDay, for: [before]); #expect(try reader.undoDate(changes) == [id])
// #expect(fetch.range == .unplaced, "the resolver erases a guess that nothing supports; decision 2")
@Test func undoPlacesAgainAMemoryThatPointedAtTheChangedOne() throws
// "The beach" (no anchor) and "The picnic" (anchor: after "The beach"); _ = try env.runner.run(); picnicBefore = fetch(picnic).range
// changes = useDate(photoDay, for: [beach]); #expect(fetch(picnic).range.isPlaced)
// try reader.undoDate(changes); #expect(fetch(beach).range == .unplaced); #expect(fetch(picnic).range == picnicBefore)
```
- [ ] **Step 2: Run `swift test --filter "updateRanges|useDate|undo"`.** Expected: compile failures for the new names.
- [ ] **Step 3: Implement.** `updateRanges` is one `db.writer.write`: for each change, fetch, compare, update, `refreshChapterRange`. `useDate` builds one `RangeChange` for each memory with `ifCurrently: memory.range`. `undoDate` builds one with `range: change.before, ifCurrently: .fromPhoto(change.date)`. In `PhotoCardViewModel.useDate(_ offer:)`, the call becomes `_ = try reader.useDate(offer.date, for: [offer.memory])`.
- [ ] **Step 4: Run `swift test`.** Expected: all pass. Build the app scheme one time (`xcodebuild build`, same project and destination) to prove the one-line change.
- [ ] **Step 5: Commit** "Kit: a photo's date goes on several memories in one write, and comes off again".

### Task 2: The card in groups, and the rules of the date part (kit)

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoStory.swift`, `Photos/PhotoStoryReader.swift`
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoDatePart.swift`, `ios/LifelineKit/Tests/LifelineKitTests/PhotoDatePartTests.swift`
- Test: `PhotoStoryTests.swift`

**Interfaces:**
- Consumes: `PhotoDateChange` (Task 1), `EntityType.screenTitle`, `PhotoCaption.longDate(_:)`, `EntityRepository.entity(id:)`.
- Produces:
```swift
// PhotoStoryCard gains three nested types, two stored fields and two computed ones:
extension PhotoStoryCard {
    public struct Page: Sendable, Equatable, Identifiable {
        public var entity: Entity
        public var isChosen: Bool                    // the page holds the photo
        public var isOwner: Bool
        public var id: EntityID { entity.id }
        public var title: String { isOwner ? "You" : entity.title }
        public var stateValue: String { isChosen ? "added" : "not added" }
    }
    public struct PageGroup: Sendable, Equatable, Identifiable {
        public var type: EntityType
        public var pages: [Page]                     // never empty; the owner first, then by title, then by id
        public var id: EntityType { type }
        public var title: String { type.screenTitle }
    }
    public struct StoryDateOffer: Sendable, Equatable {
        public var date: CivilDate
        public var memories: [Memory]                // the ones that can take the date, in telling order; never empty
    }
    public var pageGroups: [PageGroup]               // stored; in the order person, place, thing, idea; a group with no page is left out
    public var dateOffer: StoryDateOffer?            // stored
    /// "This photo goes on each moment you keep." while a moment waits; "On 1 moment from this story"; "On {n} moments from this story"; nil with nothing to say.
    public var momentsLine: String? { get }
    public var momentsLineOpens: Bool { get }        // false while a moment waits, and with no line
}
public enum PhotoStory {
    /// True when the photo has a date and the range's origin is not `stated`, `confirmed` or `photo`.
    public static func offersDate(_ date: CivilDate?, for range: TimeRange) -> Bool
    public static func card(photo: Photo, sessionMemories: [Memory], holding: Set<MemoryID>, linked: [MemoryID: [Entity]],
                            pagesWithPhoto: [Entity], ownerEntity: EntityID?, hasPendingMoments: Bool, hasOtherHome: Bool) -> PhotoStoryCard
}
public enum PhotoDatePart: Sendable, Equatable {
    public struct Offer: Sendable, Equatable {
        public var text: String
        public var button: String
        public var date: CivilDate
        public var memories: [Memory]
        public var canUndo: Bool
    }
    case hidden
    case offer(Offer)
    case used(text: String, button: String)
    /// `used`: what the taps on this screen changed. `seen`: every memory the card offered at those taps.
    public static func state(offer: PhotoStoryCard.StoryDateOffer?, holdingCount: Int, used: [PhotoDateChange], seen: Set<MemoryID>) -> PhotoDatePart
    public static func chooseButton(count: Int) -> String        // "Use for {n}"
}
```
`pagesWithPhoto` changes from `Set<EntityID>` to `[Entity]`: the card must list a page that no memory names, so it needs the entity. The reader loads each id of `subjects(of:).entities` with `entity(id:)`. The pages are the union of the entities that the holding memories name and `pagesWithPhoto`, each one time, without the ones hidden from browsing. `pageOffers`, `dateOffers` and `ownerEntity` stay until Task 4; `pageOffers` keeps its rule, and `dateOffers` follows the new `offersDate`.

`state` rules, in order: the open memories are the offer's memories that are not in `seen`. With open memories: `.offer`, with `canUndo` true when `used` is not empty. With none and `used` not empty: `.used`. Otherwise `.hidden`. The button is "Use for that one" for one, "Use for all {n}" when the open count equals `holdingCount` and is two or more, else "Use for those {n}".

**Existing tests that change, with the exact change** (`PhotoStoryTests.swift`):
- `offersDate` (the band rule goes). The helper `range(_:_:)` makes `inferred` ranges. New rows: unplaced → true (same). Photo day inside the band → **true** (was false). One day outside either edge → true (same). On an edge, both rows → **true** (was false). Nil date, both rows → false (same). `.fromPhoto(photoDay)` → false (same). Half-open, all four rows → **true** (two were false). Add: `.fromPhoto(day(2012, 6, 1))`, a date from another photo → false.
- `offersDateNeverReplacesADateThePersonSaid`: the first loop runs over `[.stated, .confirmed, .photo]`. Its assertions stay. The second loop stays, and gains the same guess with the photo day inside the band (`day(2012, 6, 14)`) → true.
- The private helper `card(...)` takes `pagesWithPhoto: [Entity] = []`. `aPageThatHoldsThePhotoIsNotOffered` passes `[maya]`; its assertion on `pageOffers` stays in this task.
- No other test of the file changes in this task.

- [ ] **Step 1: Write the failing tests.**

`PhotoStoryTests.swift`, with `pages(_ card:) = card.pageGroups.flatMap(\.pages)`:
```swift
@Test func thePagesAreInGroupsInOrder()
// one memory names idea "Saying yes", thing "The blue kayak", place "Pelican Beach", person "Maya" (given in that order)
// #expect(result.pageGroups.map(\.type) == [.person, .place, .thing, .idea])
// #expect(result.pageGroups.map(\.title) == ["People", "Places", "Things", "Ideas"])
@Test func aGroupWithNoPageIsLeftOut()                          // Maya and a place only: types == [.person, .place]
@Test func aPageThatHoldsThePhotoIsChosen()
// m names Maya and Dad; pagesWithPhoto: [maya]
// #expect(pages(result).map(\.title) == ["Dad", "Maya"]); #expect(pages(result).map(\.isChosen) == [false, true])
// #expect(pages(result).map(\.stateValue) == ["not added", "added"])
@Test func aPageThatHoldsThePhotoAndNoMemoryNamesIsListedChosen()
// m names Dad; pagesWithPhoto: [maya]; titles == ["Dad", "Maya"]; isChosen == [false, true]
@Test func aHiddenPageThatHoldsThePhotoIsNotListed()             // pagesWithPhoto: [entity("Hidden", hidden: true)]; pageGroups.isEmpty
@Test func aPageKeptFromTheAIIsListed()                          // excluded: true, named by m: listed, not chosen
@Test func theOwnersChipIsFirstAndReadsYou()
// m names Zed, Amy, Jo; owner: jo.id; titles == ["You", "Amy", "Zed"]; isOwner == [true, false, false]
@Test func aPageIsListedOnceWhenTwoMemoriesNameItAndItHoldsThePhoto()   // a and b name Maya; pagesWithPhoto: [maya]; one page, chosen
@Test func twoPagesWithOneTitleAreBothListed()                   // two entities "Sam": two pages, ordered by id
@Test func oneDateOfferForTheStory()
// a unplaced, b stated 2012, c inferred 2012 (the photo day 14 July 2019 is outside), d from another photo; all hold the photo
// #expect(result.dateOffer == .init(date: day(2019, 7, 14), memories: [a, c]))
@Test func noDateOfferWhenNoMemoryCanTakeIt()                    // b and d only: dateOffer == nil
@Test func noDateOfferWithoutAPhotoDate()                        // photo(taken: nil): dateOffer == nil
@Test func aMemoryWithoutThePhotoIsNotInTheDateOffer()           // holding: [a.id] of [a, c]: memories == [a]
@Test func theMomentsLine()
// pending, no memory → ("This photo goes on each moment you keep.", opens false); pending with one kept → the same
// one kept → ("On 1 moment from this story", true); five kept → ("On 5 moments from this story", true); none, not pending → (nil, false)
@Test func theReaderListsAPageThatHoldsThePhotoAndNoMemoryNames() throws
// StoryFixture; kept names Dad; f.store.photos.link(subject, to: .entity(maya)); the card's pages: Dad not chosen, Maya chosen
```
`PhotoDatePartTests.swift` (`d = 14 July 2019`; `m(n)` makes n unplaced memories):
```swift
@Test func theDatePart() // table: (offer memories, holdingCount, used, seen) → state
// nil, 2, [], [] → .hidden
// 1 of 2 → offer: "The photo is dated 14 July 2019. One moment has no date you said.", "Use for that one", canUndo false
// 2 of 3 → "The photo is dated 14 July 2019. Two moments have no date you said.", "Use for those 2"
// 3 of 3 → "…Three moments have no date you said.", "Use for all 3"
// 1 of 1 → "Use for that one"
// 12 of 13 → "…Twelve moments have no date you said.", "Use for those 12"; 13 of 14 → "…13 moments have no date you said.", "Use for those 13"
// after a tap: nil, 3, used 2, seen those 2 → .used("The photo is dated 14 July 2019. Two moments now use that date.", "Used for those 2")
// after a tap: nil, 1, used 1 → .used("…One moment now uses that date.", "Used for that one")
// after a tap, a memory kept later: offer [c], 3, used [a, b], seen [a, b] → offer for [c]: "One moment has no date you said.", "Use for that one", canUndo true
// after a tap, one left unchecked: offer [b], 2, used [a], seen [a, b] → .used("…One moment now uses that date.", "Used for that one")
// after a tap, the store moves on: offer nil, 2, used [a, b] while a now has a said date → still "Two moments now use that date."
@Test func theOfferCarriesItsMemoriesAndDate()                   // .offer(o): o.memories == the open ones in order; o.date == d
@Test func chooseButton()                                        // 1 → "Use for 1"; 3 → "Use for 3"
```
- [ ] **Step 2: Run `swift test --filter "PhotoStory|PhotoDatePart|offersDate|theDatePart"`.** Expected: compile failures, then the changed rows of `offersDate` fail.
- [ ] **Step 3: Implement.** The count word is a private function of `PhotoDatePart` (decision 6). The date text falls back to "that day" when `PhotoCaption.longDate` gives nil, as the card does today.
- [ ] **Step 4: Run `swift test`.** Expected: all pass. Run `PhotoCardUITests` one time: the old view now offers a date for a guess inside its band; the seed has none, so the class must pass unchanged.
- [ ] **Step 5: Commit** "Kit: the photo card's pages in groups, and one date offer for the story".

### Task 3: Reorder, and the key photo as the first photo (kit)

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/PhotoRepository.swift`, `Photos/PhotoLibrary.swift`
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoOrder.swift`, `ios/LifelineKit/Tests/LifelineKitTests/PhotoOrderTests.swift`
- Test: `PhotoRepositoryTests.swift`

**Interfaces — produces:**
```swift
extension PhotoRepository {
    /// One write. The page's photos get `sort_order` 0, 1, 2…: first the ids of `photos` that the page holds, each one time, in the
    /// order given; then the page's other photos in the order a read shows them today. The first is the cover.
    public func reorder(_ photos: [PhotoID], of subject: PhotoSubject) throws
    /// Moves the photo to the front: `reorder([photo], of: subject)`. A photo the page does not hold changes nothing.
    public func setCover(_ photo: PhotoID, of subject: PhotoSubject) throws
}
extension PhotoLibrary {
    public func reorder(_ photos: [PhotoID], of subject: PhotoSubject) throws
}
public enum PhotoOrder {
    /// The order after `photo` moves to `index` (clamped to the row). Nil when the photo is not in the row or does not move.
    public static func moving(_ photo: PhotoID, to index: Int, in order: [PhotoID]) -> [PhotoID]?
}
```
The write, in this order, because `photo_link_entity_cover` and `photo_link_memory_cover` allow one cover for each page: (1) read the page's rows in today's read order (`role = 'cover' desc, sort_order, rowid`); (2) with no row, stop; (3) set every `cover` row of the page to `attached`; (4) set each row's `sort_order` to its new index; (5) set the first row to `cover`. `link` still gives a new photo `max(sort_order) + 1`, so the write must number from 0 with no gap. `photos(of:)`, `removeLink` and `link` do not change.

`setCover` for a photo that the page does not hold must write nothing at all, as it does today: it must not renumber the page.

- [ ] **Step 1: Write the failing tests.**

`PhotoRepositoryTests.swift` (uses `Fixture`, `photo(_:at:)`). `rows(of:)` is a new private helper: `select photo_id, sort_order, role from photo_link where entity_id = ? order by sort_order, rowid`, as `[(PhotoID, Int, String)]`.
```swift
@Test func reorderSetsTheOrderAndTheCover() throws
// Maya holds a, b, c; reorder([c, a, b]); #expect(photos(of:).map(\.id) == [c.id, a.id, b.id]); isCover == [true, false, false]
// #expect(rows.map(\.1) == [0, 1, 2]); #expect(rows.map(\.2) == ["cover", "attached", "attached"])
@Test func reorderMovesTheCoverWithoutBreakingTheIndex() throws
// a is the cover; reorder([b, a, c]) must not throw; exactly one row has role cover, and it is b
@Test func reorderIgnoresWhatThePageDoesNotHoldAndKeepsWhatWasLeftOut() throws
// Maya holds a, b, c; x is on Dad only; reorder([c.id, x.id, c.id]) → [c, a, b]; Dad's rows are unchanged; x is not on Maya
@Test func reorderOnAnEmptyPageChangesNothing() throws           // no throw; no row
@Test func reorderKeepsOtherPagesAndTheMemorySubject() throws
// a is on Maya and on the memory "The tree house" with b; reorder on .memory([b, a]) → the memory's cover is b; Maya's rows are unchanged
@Test func aShelfWhoseCoverIsNotFirstIsRepairedByTheNextChange() throws
// a, b, c added; raw SQL makes the old shape: a attached, c cover (sort_order still 0, 1, 2). A read shows [c, a, b].
// setCover(b) → photos == [b, c, a]; rows == [(b, 0, "cover"), (c, 1, "attached"), (a, 2, "attached")]
@Test func equalSortOrdersAreRepaired() throws                   // raw SQL sets b and c to sort_order 1; reorder([]) keeps the read order and writes 0, 1, 2
@Test func setCoverMovesThePhotoToTheFront() throws              // a, b, c; setCover(c) → rows == [(c, 0, cover), (a, 1, attached), (b, 2, attached)]
@Test func movingTheCoverAwayMakesTheNextFirstPhotoTheCover() throws    // reorder([b, c, a]): cover is b
@Test func setCoverOfAPhotoThePageDoesNotHoldWritesNothing() throws
// raw old shape as above; setCover(x) for x on Dad only; Maya's rows are exactly the old shape (not renumbered)
@Test func aPhotoPutBackOnAPageComesBackLast() throws
// Maya holds a (cover) and b; unlink a → b is the cover; link a again → photos == [b, a]; roles == [.cover, .attached]
@Test func aPhotoPutBackOnAnEmptyPageIsItsCover() throws         // a is on Maya and on Dad, so its row stays; unlink from Maya; link again → Maya's roles == [.cover]
@Test func aNewPhotoGoesLastAfterAReorder() throws               // reorder([c, a, b]); insert d linking to Maya → [c, a, b, d]; d has sort_order 3
@Test func reorderIsOneWrite() throws                            // trace as `usingTheDateIsOneWrite` does: one BEGIN IMMEDIATE
```
`theFirstPhotoIsTheCoverAndTheRestFollowInOrder` and `makingAnUnlinkedPhotoTheCoverChangesNothing` must pass unchanged.

`PhotoOrderTests.swift`:
```swift
@Test func moving() // table, order [a, b, c]:
// (c, 0) → [c, a, b]; (a, 2) → [b, c, a]; (b, 0) → [b, a, c]; (b, 1) → nil; (a, 0) → nil; (c, 9) → nil (clamped to its own place)
// (a, 9) → [b, c, a]; (c, -3) → [c, a, b]; (x, 0) → nil; a row of one, (a, 0) → nil; an empty row → nil
```
- [ ] **Step 2: Run `swift test --filter "reorder|setCover|PutBack|moving|Repaired|aNewPhotoGoesLast"`.** Expected: compile failures, then `setCoverMovesThePhotoToTheFront` and the repair tests fail.
- [ ] **Step 3: Implement.** One private static `writeOrder(_ wanted: [PhotoID], of subject: PhotoSubject, in db: Database)` holds the five steps; `reorder` and `setCover` call it inside one `db.writer.write`.
- [ ] **Step 4: Run `swift test`.** Expected: all pass, with every merge and undo test of `PhotoRepositoryTests.swift` unchanged.
- [ ] **Step 5: Commit** "Store: a page's photos have one stored order, and the first is the cover".

### Task 4: The card in one layout (app)

**Files:**
- Modify: `ios/Lifeline/Screens/Photos/PhotoCard.swift`, `PhotoCardViewModel.swift`, `ios/Lifeline/UITestSeed.swift`, `ios/Lifeline/Dependencies.swift` (the new flag); `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoStory.swift` and `PhotoStoryReader.swift` (remove the old fields)
- Create: `ios/Lifeline/Screens/Photos/PhotoCardPages.swift` (part 2), `PhotoCardDate.swift` (part 3), `PhotoCardMomentsSheet.swift` (one sheet, two modes)
- Test: `ios/LifelineUITests/PhotoCardUITests.swift`, `ios/LifelineKit/Tests/LifelineKitTests/PhotoStoryTests.swift`

**Interfaces:**
- Consumes: `PhotoStoryCard.pageGroups`, `dateOffer`, `momentsLine`, `momentsLineOpens`; `PhotoDatePart.state`; `PhotoStoryReader.addToPage`, `useDate(_:for:)`, `undoDate(_:)`; `PhotoLibrary.remove(_:from:)`, `removeFromStory(_:)`; `FlowLayout`.
- Produces:
```swift
// PhotoCardViewModel
var datePart: PhotoDatePart { get }                       // PhotoDatePart.state(offer: card?.dateOffer, holdingCount: card?.memories.count ?? 0, used:, seen:)
func toggle(_ page: PhotoStoryCard.Page) async            // chosen: deps.photos.remove(photo, from: .entity(page.id)); else reader.addToPage
func useDate(for memories: [Memory])                      // from the offer's date; on a change: used += changes, seen += every offered memory
func undoDate()                                           // reader.undoDate(used); then used and seen are empty
// unchanged: refresh(), removeFromMemory(_:) async, removeFromStory() async, card, isLoaded, error, showsRemoveFromStory
// removed: addToPage(_:), offerTitle(_:), useDate(_ offer:)

struct PhotoCardPages: View { let groups: [PhotoStoryCard.PageGroup]; let onToggle: (PhotoStoryCard.Page) -> Void }
struct PhotoCardDate: View { let part: PhotoDatePart; let onUse: ([Memory]) -> Void; let onChoose: () -> Void; let onUndo: () -> Void }
struct PhotoCardMomentsSheet: View {
    enum Mode { case holding(remove: (Memory) -> Void), choosing(use: ([Memory]) -> Void) }
    let title: String; let memories: [Memory]; let mode: Mode
}
```
Kit removals: `PhotoStoryCard.pageOffers`, `dateOffers`, `ownerEntity` and the nested `DateOffer` (one offer for one memory). `StoryDateOffer` keeps its name. `PhotoStory.card` keeps its `ownerEntity:` parameter.

The card's parts, in the spec's order: the photo with its caption and the moments row; `PhotoCardPages`; `PhotoCardDate`; "Remove the photo from this story". The card draws no memory row. `photoCard.pending` is the row while a moment waits (a text, not a button). `photoCard.moments` is the row when it opens. A chip is a button with the identifier `photoCard.page`, the label `page.title` and the accessibility value `page.stateValue`. A group's name is a text with the identifier `photoCard.group`. In the "used" state, `photoCard.dateUsed` is a text with a tick, not a button, in the frame that `photoCard.useDate` had; `photoCard.undoDate` sits where `photoCard.chooseMoments` sat. In the choosing mode, every `photoCard.chooseMoment` toggle starts on, `photoCard.useChosen` reads `PhotoDatePart.chooseButton(count:)` and is disabled at zero.

The seed. `-uiTesting-seedPhotoStory` does not change. A new flag, `-uiTesting-photoStoryGuess`, read with it, adds a third kept memory to the first story: "The picnic", an event that names Maya and Alder Street, holds the story's photo, and has a guessed date with an anchor. `SeedSession.keep` gains an optional age anchor. The anchor is the age phrase "when I was 22" (Jordan was born on 1 June 1990, so the band holds 14 June 2012). The seeded range must be the range the resolver gives that anchor: build it with `TimeRange.stated(age:birth:evidence:)` and set its origin to `inferred`. If `AnchorPhrase.parseAge("when I was 22", value: "22")` is not 22, choose a phrase that is. `testUndoPutsTheDatesBack` fails when the two differ.

**Existing kit tests that change, with the exact change** (`PhotoStoryTests.swift`; `pages(_:)` as in Task 2):
- `aPageThatHoldsThePhotoIsNotOffered`: removed. `aPageThatHoldsThePhotoIsChosen` (Task 2) asserts more: Dad is listed not chosen and Maya is listed chosen.
- `aPageIsOfferedOnceWhenTwoMemoriesNameIt`: `pages(result).count == 2` and `Set(pages(result).map(\.id)) == [maya.id, house.id]`; add `result.pageGroups.map(\.type) == [.person, .thing]`.
- `theOwnersPageLeadsTheOffers`: removed; `theOwnersChipIsFirstAndReadsYou` (Task 2) has the same input and asserts the order with the owner's new title.
- `aHiddenPageIsNotOffered`: `pages(result).map(\.id) == [kept.id]`.
- `aMemoryWithoutThePhotoGetsNoDateOffer`: `result.dateOffer?.memories.map(\.id) == [holds.id]` and `result.dateOffer?.date == day(2019, 7, 14)`.
- `aPhotoWithNoDateOffersNoDate`: `card(photo(taken: nil), memories: [m]).dateOffer == nil`.
- `theCardNamesTheOwnersPage`: `pages(card(…, owner: me.id)).map(\.isOwner) == [true, false]`, and with no owner `[false, false]`.
- `theReaderSeesAMemoryKeptLater`: `after.dateOffer?.memories.map(\.id) == [kept.id]`.
- `theCardListsAMemoryATellingWasMergedInto`: `pages(card).map(\.id) == [dad.id]` with `isChosen == [false]`; `card.dateOffer?.memories.map(\.id) == [target.id]`.
- `theReaderOffersTheNamedPagesAndTheDateAndAppliesTaps`: before, `pages(card).map(\.id) == [maya.id]` with `isChosen == [false]`; the tap uses `card.dateOffer`; after, `pages(after).map(\.isChosen) == [true]` (the page stays, chosen) and `after.dateOffer == nil`. The range and `hasOtherHome` assertions stay.

**Existing UI tests that change, with the exact change** (`PhotoCardUITests.swift`). The helper `cardMemoryTitles` now opens `photoCard.moments`, reads the `photoCard.memory` labels in `photoCard.momentsSheet`, and taps `photoCard.momentsDone`. The helper `useDateBlocks` is replaced by a query for `photoCard.date`.
- `testAKeptMomentHoldsThePhoto`: after the first card is kept, the memory's page still shows the photo (same). Back on the landing, `photoCard.pending` still shows, because one moment waits (decision 9). The test then keeps the second card, goes back, and asserts `photoCard.moments` has the label "On 2 moments from this story" and the sheet lists both kept titles.
- `testTheCardOnTheSessionsPage`: the titles assertion stays through the new helper; add the row's label "On 2 moments from this story". The page assertions become: one `photoCard.group` with the label "People"; the `photoCard.page` labels are ["Dad", "Maya"] with the values ["not added", "added"].
- `testAddToAPagePutsThePhotoThere`: tap the chip "Dad"; its value becomes "added" and the chip stays; Dad's page shows `photo.header` (same).
- `testTheDateIsOfferedOnlyWhereItHelps` (one offer for each memory) becomes `testOneDateBlockForTheStory`, launched with `-uiTesting-photoStoryGuess`: exactly one `photoCard.date`; `photoCard.dateText` reads "The photo is dated 14 June 2012. Two moments have no date you said."; `photoCard.useDate` has the label "Use for those 2"; `photoCard.chooseMoments` has the label "Choose moments"; no text "The beach" and no text "The drive home" is inside `photoCard.date`.
- `testUseThisDateDatesTheMemory` (default seed): `photoCard.dateText` reads "The photo is dated 14 June 2012. One moment has no date you said."; tap `photoCard.useDate` ("Use for that one"); `photoCard.dateText` then reads "The photo is dated 14 June 2012. One moment now uses that date."; `app.staticTexts["photoCard.dateUsed"]` has the label "Used for that one" and `app.buttons["photoCard.dateUsed"]` does not exist; `photoCard.undoDate` has the label "Undo". The three assertions on the memory's page stay.
- `testRemoveTakesThePhotoOffOneMemory`: the test opens the sheet, asserts two `photoCard.removeFromMemory` buttons, taps "Remove from The drive home" and closes the sheet. Then: the row reads "On 1 moment from this story"; the chip "Dad" still exists with "not added"; `photoCard.dateText` still reads "…One moment has no date you said.". The two memory-page assertions stay.
- `testKeepItLeavesThePhotoOnTheStory`: the last assertion goes through the new helper (same titles).
- `testTheCardHoldsAtTheLargestText`: the identifiers become `photoCard.moments`, `photoCard.page`, `photoCard.useDate`, `photoCard.chooseMoments` and, on the session's page, `photoCard.removeFromStory`; then the test taps `photoCard.useDate` and checks `photoCard.undoDate` the same way. The rule (reachable, at least 44 points high, the last control above the record bar) stays.
- `testTheLandingSaysThePhotoGoesOnWhatYouKeep`, `testTellItsStoryIsNotOfferedInsideALandingsReview`, `testRemoveThePhotoFromThisStory`, `testDeletingAStorySaysWhenItsPhotoGoes` and `testAnOrdinarySessionHasNoCard` must pass unchanged.

- [ ] **Step 1: Write the failing tests.** Change the tests above. Add, in `PhotoCardUITests` (launch `launchWithPhotoStory(["-uiTesting-photoStoryGuess"])` unless it says otherwise, then `openFirstStory`):
  - `testThePagesAreInGroups`: the `photoCard.group` labels are ["People", "Places"]; the `photoCard.page` labels are ["Dad", "Maya", "Alder Street"]; the texts "Also show this photo on" and "Tap to add. Tap again to take it off." exist; each group's name is above its first chip.
  - `testAChipAddsAndTakesOff`: "Dad" is "not added"; tap; "added"; Dad's page has `photo.header`; back; tap again; "not added"; Dad's page has no `photo.header`.
  - `testAChosenChipTakesThePhotoOffAPageThatHeldIt` (default seed): "Maya" is "added"; tap; "not added"; `photoCard` still exists and "The beach" still shows `photo.thumb`; tap again; "added".
  - `testUndoPutsTheDatesBack`: read the `memory.range` label of "The picnic" and of "The beach"; tap `photoCard.useDate`; `photoCard.dateText` reads "…Two moments now use that date."; both memory pages show "14 June 2012" and "from a photo"; back on the card `photoCard.undoDate` still exists; tap it; `photoCard.dateText` reads "…Two moments have no date you said." and `photoCard.useDate` reads "Use for those 2"; both `memory.range` labels equal the first reading.
  - `testChooseMomentsUsesOnlyTheCheckedOnes`: tap `photoCard.chooseMoments`; the sheet has two `photoCard.chooseMoment` switches, labeled "The beach" and "The picnic", both on, and `photoCard.useChosen` reads "Use for 2"; turn both off: the button is not enabled; turn "The beach" on: the button reads "Use for 1"; tap it; the sheet closes; `photoCard.dateText` reads "…One moment now uses that date." and `photoCard.dateUsed` reads "Used for that one" (decision 5: the unchecked memory does not bring the offer back); "The picnic" keeps its first `memory.range` label; "The beach" shows "from a photo".
  - `testTheCardKeepsItsLayoutAfterEachChoice`: record the frames of every `photoCard.page`, of `photoCard.date`, of `photoCard.useDate` and of `photoCard.chooseMoments`, and the `minY` of `photoCard.removeFromStory`. Tap "Dad" and tap `photoCard.useDate`. Then: every `photoCard.page` frame is equal; `photoCard.date` has the same `minY`; `photoCard.dateUsed` has the frame that `photoCard.useDate` had; `photoCard.undoDate` has the `minY` that `photoCard.chooseMoments` had; `photoCard.removeFromStory` has the same `minY`.
  - `testTheLandingsCardHasTheSameParts` (`opening: "first"`): the landing shows `photoCard.moments`, the chips and `photoCard.date`, and no `photoCard.removeFromStory`.
- [ ] **Step 2: Run `-only-testing:LifelineUITests/PhotoCardUITests`; expected FAIL** (the new identifiers do not exist).
- [ ] **Step 3: Implement.** Errors use `photoErrorSlot` through the view model's `error`, as today. After each action the card reads the store again. `undoDate` clears `used` and `seen` also when the write put back nothing.
- [ ] **Step 4: Run** `swift test`, then `PhotoCardUITests`, `PhotoStoryUITests` and `LandingUITests`. Expected: all pass. Run the guards script.
- [ ] **Step 5: Commit** "The photo card keeps one layout: chips by kind, one date offer with Undo".

### Task 5: The key photo on the page (app)

**Files:**
- Modify: `ios/Lifeline/Screens/Photos/PhotoRow.swift`, `PhotoShelf.swift`, `PhotoViewer.swift`; the three callers of `PhotoRow` (`Screens/Entities/EntityScreen.swift`, `Screens/Memory/MemoryScreen.swift`, `Screens/You/PortraitHeader.swift` with `YouScreen.swift`) and their view models (`EntityViewModel`, `MemoryViewModel`, `YouViewModel`)
- Test: `ios/LifelineUITests/PhotosUITests.swift`

**Interfaces:**
- Consumes: `PhotoLibrary.reorder(_:of:)`, `PhotoLibrary.setCover(_:of:)`, `PhotoOrder.moving(_:to:in:)` (Task 3).
- Produces:
```swift
// PhotoShelf
func reorder(_ photos: [PhotoID]) async          // deps.photos.reorder(photos, of: subject), then load(); a failure: "Could not change the order of the photos: {reason}"
func move(_ photo: PhotoID, to index: Int) async // PhotoOrder.moving(photo, to: index, in: photos.map(\.id)); nil: no call, no write
// makeCover(_:) keeps its name; its failure line becomes "Could not make this the key photo: {reason}"

struct PhotoRow: View {
    let photos: [PlacedPhoto]
    let label: String
    let cache: PhotoImageCache
    let onOpen: (PlacedPhoto) -> Void
    let onMove: (PhotoID, Int) -> Void           // the photo and the index where the drag ended
}
```
Each page's view model gets `movePhoto(_:to:)`, shaped as its `makeCover(_:)` is (it clears the page's error, calls the shelf, and the screen calls `onChange()` where `makeCover` does).

The row: with two or more photos, the line `photo.shelfHint` sits between the heading "Photos" and the tiles. The first tile carries the pill `photo.keyLabel` ("Key photo", decision 11). The pill is its own accessibility element, read next to the tile; the tiles keep their labels and values. Every tile except the first has the accessibility action "Move to front", which calls `onMove(id, 0)`. A long press and then a drag moves a tile; the row shows where it will land; on release the row calls `onMove` with the index under the finger. A tap opens the viewer as today. With one photo there is no line, no drag and no action. In the viewer, `photo.makeCover` reads "Make this the key photo"; the doc comments of `PhotoViewer`, `PhotoShelf` and `PhotoRow` say "key photo" for what the person reads.

**Existing tests that change** (`PhotosUITests.swift`): `testMakeThisTheCoverChangesTheHeader` gains two assertions and loses none: `app.buttons["photo.makeCover"].label == "Make this the key photo"` before the tap, and after it the `photo.thumb` values are ["", "taken 14 June 2012"]. Every other test of the class must pass unchanged; `testSeveralPhotosShowInARow` pins that each tile keeps its label and its caption value.

- [ ] **Step 1: Write the failing tests** (`PhotosUITests`, launch `launchWithPhotos()`, open Maya, reveal "Photos"):
  - `testTheShelfSaysWhichPhotoIsTheKeyPhoto`: `photo.shelfHint` has the label "The first photo is the key photo. Hold a photo and drag it to the front to change it."; it is below the heading "Photos" and above the first `photo.thumb`; `photo.keyLabel` has the label "Key photo" and its frame is inside the first thumb's frame.
  - `testDraggingAPhotoToTheFrontChangesTheKeyPhoto`: `thumbs.element(boundBy: 1).press(forDuration: 1.0, thenDragTo: thumbs.element(boundBy: 0))`; `photo.viewer` does not exist; `photo.header` gets the value "" (the undated photo); after `reveal`, the thumb values are ["", "taken 14 June 2012"]; leave the page and open it again: the order holds.
  - `testDraggingTheKeyPhotoAwayMakesTheNextOneTheKeyPhoto`: drag the first thumb onto the second; the header's value becomes "".
  - `testADragThatEndsWhereItStartedChangesNothing`: press the second thumb for one second and drag it a few points; the values stay ["taken 14 June 2012", ""]; no `photo.error`; no `photo.viewer`.
  - `testATapOnAThumbStillOpensTheViewer`: after one drag, a tap on the second thumb opens `photo.viewer`.
  - `testOnePhotoHasNoHintAndNoDrag`: on the memory "The tree house" (one photo, the row shows): `photo.thumb` exists, `photo.keyLabel` exists, `photo.shelfHint` does not exist; a long press and drag changes nothing.
  - `testTheShelfHoldsAtTheLargestText` (XXXL): `photo.shelfHint` is reachable and its height is more than 44 points (it wraps, it does not clip); each thumb is at least 44 points high.
- [ ] **Step 2: Run `-only-testing:LifelineUITests/PhotosUITests`; expected FAIL.**
- [ ] **Step 3: Implement.** The tile stays a `Button` for the tap; the long-press-then-drag gesture is added with `simultaneousGesture` or as a high-priority gesture, whichever keeps both tests green: `testATapOnAThumbStillOpensTheViewer` and `testDraggingAPhotoToTheFrontChangesTheKeyPhoto`. The horizontal scroll of the row must still work with a plain swipe.
- [ ] **Step 4: Run** `swift test`, then `PhotosUITests`, `EntityPageUITests`, `YouUITests` and `PhotoStoryUITests` (it opens a cover in the viewer). Expected: all pass. Run the guards script.
- [ ] **Step 5: Commit** "The first photo is the key photo: drag it, or move it to the front".

### Task 6: Docs, screenshots and the device check

**Files:**
- Modify: `docs/DECISIONS.md`, `docs/OVERVIEW.md` ("The shape of the app", "Photos", "A photo starts a story"), `docs/specs/2026-11-18-photo-card-key-photo.md` (the status line only: "Approved by the owner on 2026-11-18")
- Create: `docs/plans/2026-11-18-photo-card-key-photo-device-check.md`, `docs/screenshots/photo-card/`

- [ ] **Step 1: `docs/DECISIONS.md`**, a new entry at the top: "2026-11-18 · The photo card has one layout, and the first photo is the key photo". It must state: the four problems the owner found; the chosen approach and the two that were not chosen; the new date rule (origin, not band) and that it replaces "outside the band" of the 2026-11-16 entry; that Undo is kept in memory and what the resolver does to a guess with no anchor (decision 2), as an open item for the owner; "key photo" for "cover" in every text the person reads, with the code names kept; `setCover` as a move to the front, with no migration; decisions 3 to 5, 9 and 14 of this plan as open items; the seven points agreed with `docs/specs/2026-11-18-people-contacts.md`; every ruling made while building.
- [ ] **Step 2: `docs/OVERVIEW.md`**, in ASD-STE100 style. "Photos": the first photo is the key photo; the shelf's line; the drag, the viewer button and the VoiceOver action; `sort_order` is the stored order and `reorder` writes it from 0. "A photo starts a story": the card's four parts; the date rule; one write for several memories; Undo while the screen is open. Replace "cover" with "key photo" where the text describes what the person reads, and keep `cover` where it names the role in the data model.
- [ ] **Step 3: The device checklist**, numbered, each line with what to do and what must be true: a story with five kept memories shows one date block and one moments row; "Use for those {n}", then Undo, then the memory pages show their first dates; "Choose moments" with one unchecked; a chip added and taken off, and the page checked each time; a chip for a page that held the photo before the story; a moment moved to another person, and both chips show; the card at the largest text size on the landing and on the session's page; VoiceOver on the card (each chip reads its name and "added" or "not added"; the used button is not a control); a drag on the shelf of a person, a memory and You, with a tap and a sideways scroll still working; the drag with a finger that leaves the row; VoiceOver's "Move to front" on each tile except the first (decision 14); "Make this the key photo" in the viewer; a page whose cover was chosen before this build, then one drag; the People grid shows the new key photo; a kill after "Use for those", then the next launch.
- [ ] **Step 4: Screenshots** with invented data, from the seed with `-uiTesting-photoStoryGuess`: the card before a choice; the card after a chip and the date tap; the moments sheet; "Choose moments"; the shelf with its line and the "Key photo" label; the viewer with "Make this the key photo".
- [ ] **Step 5: Commit** "Docs: the photo card in one layout, and the key photo".

## After this plan

- The controller runs the whole UI suite one time and the guards script, then asks the owner before a PR. Nothing is pushed without the owner's word.
- `docs/specs/2026-11-18-people-contacts.md` ships second and must follow the seven points of the spec's section "Together with the people and contacts spec".
- A stored Undo, a "declined" state for an offer, and a grid for the shelf are not in this plan.
