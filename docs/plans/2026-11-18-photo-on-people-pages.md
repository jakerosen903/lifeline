# A photo story's photo goes on the pages of its people: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the owner keeps a moment of a photo story, the photo goes on the page of each person the moment names; the card shows it, one tap takes it off, and the photo follows a name the owner moves.

**Architecture:** One additive migration stores which photo link a story made (`photo_link.origin`) and which page the owner took a photo off (`photo_page_declined`). The page links are written inside the write that keeps the moment. The move of a name (`PersonLinkWrites`) moves the story's link in its own write and its receipt carries the change for Undo. The card model gains one flag per page and one line of text. The views hold no rule.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), LifelineKit (GRDB 7, Swift Testing), XCUITest.

**Spec:** `docs/specs/2026-11-18-photo-on-people-pages.md` (approved by the owner on 2026-11-18, approach A).

**Base:** branch `photo-people`, which holds `photo-card` (PR #31), `main`, and PC-a of the people and contacts work. A PR for this work can open only after PR #31 and PC-a are on `main`.

## Decisions made in this plan

1. The migration is `v16`. It follows `v14` (photo story) and `v15` (people and contacts). PC-b adds no migration. If another `v16` reaches `main` first, this one is renumbered before the PR.
2. `photo_link.origin` is text. `story` marks a link a photo story made. Null marks every other link. An owner's tap never writes `story`.
3. `photo_page_declined (photo_id, entity_id)` has both columns as its primary key. Each column references its table with `on delete cascade`.
4. Every public removal of a photo from an entity's page is the owner's action, so it records the decline. This covers the card's chip and the page's own photo row.
5. Every public add of a photo to an entity's page is the owner's action. It deletes the decline for that pair and writes a null origin.
6. Only the Keep of a card writes page links (`MemoryRepository.insert` with `acceptingCandidate`). "Same story" (a telling merged into an older memory) writes none in this plan. The people of that memory show as empty chips. This is an open item for the owner.
7. A person is skipped when the person is the owner, when the entity is hidden (`hiddenFromTimeline`), when the page holds the photo, or when the pair is declined.
8. The link goes through the existing link write, so the photo is last in the page's order, and is the key photo on a page with no photo.
9. Removing the photo from its story (`letGo`) deletes the photo's `story` links in the same write, but only when no other session points at the photo.
10. The move acts only when the moved memories' session has a subject photo and those memories hold it.
11. Undo of a move restores the photo links only where they are still as the move left them. A link the owner changed after the move stays.
12. The chip's accessibility value is "added by this story" for a `story` link, "added" for the owner's, "not added" for none.
13. The seeded photo story for UI tests is kept through the real Keep write, so its person chips now start filled. Existing UI tests that start from an empty person chip change their first step; each changed line is listed in the task report. No test is deleted and no assertion is weakened.
14. Moments kept before this build get no link. There is no backfill.
15. Part 3: `v16` also adds `session.photo_pages_done`, boolean, not null, default 0.
16. Part 3: in the done state the card keeps a chip the owner emptied on screen until the part is closed again or the card is built again by leaving the screen. The view model holds the set of such pages; it is not stored.
17. Part 4: the picker's selection is `[PhotosPickerItem]` with `maxSelectionCount: 20` and `selectionBehavior: .ordered`. Photos are received and added one after the other, never at the same time, so memory holds one image.
18. Part 4: UI tests cannot drive the picker. The launch argument `-uiTesting-pickPhoto <path>` keeps its meaning; a new `-uiTesting-pickPhotos <path>,<path>` gives several files to the same flow.

## Global Constraints

- Work only in `/Users/jakerosen/dev/lifeline/lifeline-photo-people`, branch `photo-people`. Do not push. Do not open a PR.
- The app adds no network call. The server stores nothing. All data stays on the device.
- A shipped migration block is never edited. The new block is additive: no existing row or column changes.
- Fixtures are invented (Maya, Dad, "The beach", "The picnic"). Test images come from `GeneratedPhoto`.
- Fixed copy, verbatim:
  - The line while a story chose a page: "The people in this story have this photo on their pages. Tap to take it off, or to add it to another page."
  - The line with no such page: "Tap to add. Tap again to take it off."
  - Chip values: "added by this story", "added", "not added".
  - Part 3: buttons "Done" and "Edit"; the sentence "This photo is on no other page."
  - Part 4: "Adding photo {i} of {n}…"; "{k} photos could not be added."
- Kit tests: `cd ios/LifelineKit && swift test` in full before each commit.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'platform=iOS Simulator,id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`. Only the classes a task names.
- Guards: `python3 .github/scripts/pr_guards.py origin/main` passes before each commit.
- Docs under `docs/` use ASD-STE100 style. Commits: imperative, one line; no AI attribution.
- Real TDD: each new test is seen failing for the expected reason before the code is written.

## Review Focus

1. The owner takes the photo off a page, then keeps another moment that names the same person. The photo must stay off. (Task 2)
2. A person's page holds the photo because the owner put it there before the story. A move away from that person must leave it. (Task 4)
3. A kill during Keep. The moment, its photo link and the page links are one write, so none exists without the others. (Task 2)
4. A phone that ran `v15` only, and a phone on `v13`: both reach `v16` with every row kept and every old link with a null origin. (Task 1)
5. Undo of a move after the owner tapped a chip. Undo must not remove a link the owner made or bring back one the owner took off. (Task 4)

---

### Task 1: The stored fact (kit)

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/Migrations.swift`, `Store/PhotoRepository.swift`, `Domain/Photo.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/MigrationsTests.swift`, `PhotoRepositoryTests.swift`, `BackupTests.swift`

**Interfaces — Produces:**
```swift
public enum PhotoLinkOrigin: String, Sendable, Codable { case story }

extension PhotoRepository {
    /// The entities whose link to this photo a story made.
    public func storyPages(of photo: PhotoID) throws -> Set<EntityID>
    public func isDeclined(_ photo: PhotoID, on entity: EntityID) throws -> Bool
    // Changed behaviour, same signatures:
    // link(_:to:)   an entity subject: deletes the decline for the pair; origin null; a `story` link the page already holds becomes null.
    // unlink(_:from:) an entity subject: records the decline for the pair, in the same write.
    // Inside a write:
    static func link(_ photo: PhotoID, to subject: PhotoSubject, origin: PhotoLinkOrigin?, in db: Database) throws -> Bool
}
```

- [ ] **Step 1: Failing tests.**
  - `MigrationsTests.v16KeepsEveryRowAndOldLinksHaveNoOrigin`: migrate to `v15`, insert an entity, a person, a photo and one `photo_link`; migrate; every row of `photo_link`, `photo`, `entity` is unchanged in its old columns; `origin` is null; the table `photo_page_declined` exists; `Migrations.currentSchemaVersion == "v16"`. Change `v14ThenV15AreBothRegistered` to expect the suffix `["v14", "v15", "v16"]`, and `schemaVersionsOrderByMigrationPosition` to expect `"v16"`.
  - `MigrationsTests.v16FromV13` : migrate a populated `v13` database straight to the end; no row is lost.
  - `PhotoRepositoryTests.unlinkingFromAPageRecordsTheDecline`: link, unlink; `isDeclined` is true.
  - `PhotoRepositoryTests.linkingAgainClearsTheDecline`: link, unlink, link; `isDeclined` is false; `storyPages` is empty.
  - `PhotoRepositoryTests.anOwnersLinkOverAStoryLinkMakesItTheOwners`: write a `story` link inside a write, then `link(_:to:)`; `storyPages` is empty; the page holds the photo one time.
  - `PhotoRepositoryTests.unlinkingFromAMemoryRecordsNoDecline`.
  - `PhotoRepositoryTests.deletingAPersonDeletesItsDeclines` and `deletingAPhotoDeletesItsDeclines` (cascade).
  - `BackupTests`: a backup made with a `story` link and a decline restores both.
- [ ] **Step 2:** Run the new tests; expected FAIL (no column, no table, no function).
- [ ] **Step 3:** Implement. The `v16` block: `alter table photo_link add column origin text`; create `photo_page_declined`.
- [ ] **Step 4:** `swift test`; guards. Expected: pass.
- [ ] **Step 5:** Commit "Store which photo link a story made and which page the owner took a photo off".

### Task 2: Keep puts the photo on its people's pages (kit)

**Files:**
- Modify: `Store/PhotoRepository.swift`, `Store/MemoryRepository.swift`
- Test: `PhotoStoryTests.swift`, `PhotoRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
```swift
extension PhotoRepository {
    /// Inside the Keep write, after the memory's links are stored. Puts the photo on the page of each person the memory
    /// names, with origin `story`. Skips the owner, a hidden entity, a page that holds the photo, and a declined pair.
    /// Returns the entities it linked.
    @discardableResult
    static func linkToPeoplePages(_ photo: PhotoID, namedBy memory: MemoryID, in db: Database) throws -> [EntityID]
}
```
`MemoryRepository.insert(… acceptingCandidate:)` calls it when `linkSubjectPhoto` returns a photo. `letGo(of:)` follows decision 9.

- [ ] **Step 1: Failing tests** (`PhotoStoryTests`, with `StoryFixture`; keep through `CandidateActions.acceptMemory`):
  - `keepingAMomentPutsThePhotoOnItsPeoplesPages`: the card names Maya and Dad; after Keep, both pages hold the photo; `storyPages == [maya, dad]`.
  - `thePhotoIsTheKeyPhotoOnAPageWithNoPhoto` and `thePhotoGoesLastOnAPageWithPhotos` (roles `[.cover]`; `[.cover, .attached]` with the story photo second).
  - `theOwnersPageIsSkipped`, `aHiddenPersonIsSkipped`, `aPlaceIsSkipped` (the moment names Alder Street; its page does not hold the photo).
  - `aPageThatHoldsThePhotoKeepsItsOwnersLink`: the owner linked the photo to Maya before Keep; after Keep `storyPages` does not contain Maya and the page holds the photo one time.
  - `aPhotoTakenOffStaysOffAfterTheNextKeep`: keep moment one (names Maya); `unlink` from Maya; keep moment two (names Maya); Maya's page does not hold the photo.
  - `anAssumedNameAlsoPlacesThePhoto`: the link's origin is `.assumed`; the page holds the photo.
  - `aStoryWithNoPhotoWritesNoPageLink`.
  - `aFailedKeepWritesNothing`: force the insert to throw after the links (a duplicate span); no memory, no `photo_link` row for the entity.
  - `sameStoryWritesNoPageLink` (decision 6): `MergeActions` "Same story" into an older memory; the people's pages do not hold the photo.
  - `removingThePhotoFromTheStoryRemovesItsStoryLinks`: keep (Maya gets a `story` link), the owner links the photo to Dad, `letGo`; Maya's page does not hold the photo; Dad's page holds it; the photo row remains.
  - `removingThePhotoKeepsStoryLinksWhenAnotherSessionPointsAtIt`.
- [ ] **Step 2:** Run; expected FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test`; guards. Kit tests of earlier work that count a person's photos after Keep can change: list each changed line in the report, with the reason.
- [ ] **Step 5:** Commit "Keeping a moment of a photo story puts the photo on its people's pages".

### Task 3: The card shows what the story chose (kit)

**Files:**
- Modify: `Photos/PhotoStory.swift`, `Photos/PhotoStoryReader.swift`
- Test: `PhotoStoryTests.swift`

**Interfaces — Produces:**
```swift
extension PhotoStoryCard.Page {
    public var byStory: Bool            // the page holds the photo through a `story` link
    // stateValue: "added by this story" | "added" | "not added"
}
extension PhotoStoryCard {
    public var pagesLine: String        // the two fixed lines of Global Constraints
}
// PhotoStory.card gains `storyPages: Set<EntityID>`; PhotoStoryReader.card passes `store.photos.storyPages(of:)`.
// PhotoStoryReader gains:
public func removeFromPage(_ photo: PhotoID, _ entity: EntityID) throws -> Photo?   // unlink; records the decline
```
If `removeFromPage` exists under another name, keep that name and state it in the report.

- [ ] **Step 1: Failing tests:** `aPageTheStoryChoseReadsAddedByThisStory`; `aPageTheOwnerTappedReadsAdded`; `theLineNamesTheStorysChoiceWhileOnePageHasIt`; `theLineIsThePlainOneWithNoStoryPage`; `byStoryIsFalseForAPageThatDoesNotHoldThePhoto` (a stale id in `storyPages`); through the reader: keep, then `card(for:)` has Maya `isChosen && byStory`; `removeFromPage`, then the card has Maya not chosen and the plain line; `addToPage`, then Maya is chosen and not `byStory`.
- [ ] **Step 2:** Run; expected FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test`; guards.
- [ ] **Step 5:** Commit "The photo card says which pages the story chose".

### Task 4: The photo follows a moved name (kit)

**Files:**
- Modify: `Store/PersonLinkWrites.swift`, `Confirmation/PersonLinkActions.swift` (the receipt), `Store/PhotoRepository.swift`
- Test: `PersonLinkActionsTests.swift` (or the file that tests `move` and `undo` today), `PhotoStoryTests.swift`

**Interfaces — Produces:**
```swift
public struct PhotoPageChange: Sendable, Equatable {
    public var photo: PhotoID
    public var added: [EntityID]        // pages the move put the photo on (origin `story`)
    public var removed: [EntityID]      // pages the move took the story's link from
}
extension PersonMoveReceipt { public var photoPages: PhotoPageChange? }   // nil: the move touched no photo link
```
Inside `PersonLinkWrites.move(… in db:)`, after the name links are written: for the subject photo of the moved memories' session, when those memories hold it —
- add: `linkToPeoplePages` for the moved memories (the new person, by the rules of Task 2);
- remove from the first person's page when the link is `story` and no memory of that session that holds the photo names the first person now. This removal records no decline.
Inside `undo(_:in:)`: delete each `added` link that is still `story`; put back each `removed` link, as `story`, when the page does not hold the photo and the pair is not declined.

- [ ] **Step 1: Failing tests:**
  - `movingANameMovesTheStorysPhoto`: keep a moment that names Dad (assumed); move to "Someone new"; the new person's page holds the photo (`story`); Dad's page does not; `receipt.photoPages == .init(photo:, added: [new], removed: [dad])`.
  - `aMoveToAPersonOnFileMovesThePhoto`.
  - `notAPersonRemovesTheStorysLinkAndAddsNone`.
  - `theFirstPersonKeepsThePhotoWhileAnotherMomentNamesThem`: two kept moments name Dad; move one, `wholeGroup: false`; Dad's page still holds the photo; the new person's page holds it.
  - `aMoveLeavesAnOwnersLink`: the owner linked the photo to Dad before the story; after the move Dad's page holds it; `removed` is empty.
  - `aMoveDoesNotAddToADeclinedPage`: the owner took the photo off Maya; a move to Maya adds no link.
  - `aMoveInAStoryWithNoPhotoTouchesNoPhotoLink` (`photoPages == nil`).
  - `theRemovalRecordsNoDecline`.
  - `undoPutsThePhotoBack`: after undo Dad's page holds the photo (`story`) and the new person is gone, as today.
  - `undoLeavesALinkTheOwnerMadeAfterTheMove`: move; the owner taps the new person's chip off and on (now the owner's link) — undo to a person on file leaves that link.
  - `undoDoesNotBringBackAPhotoTheOwnerTookOff`: move to a person on file; the owner links then unlinks the photo on the first person's page; undo adds no link there.
  - Every existing test of `move` and `undo` passes unchanged.
- [ ] **Step 2:** Run; expected FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test`; guards.
- [ ] **Step 5:** Commit "A photo story's photo follows a name the owner moves".

### Task 5: The card on screen, and the docs (app)

**Files:**
- Modify: `ios/Lifeline/Screens/Photos/PhotoCardPages.swift`, `PhotoCardViewModel.swift` (the chip's remove goes through `removeFromPage`), `ios/Lifeline/UITestSeed.swift` only if a seed needs a declined or owner's link
- Test: `ios/LifelineUITests/PhotoCardUITests.swift`, `PeopleGuessUITests.swift`
- Docs: `docs/DECISIONS.md` (new entry at the top: "2026-11-18 · A photo story's photo goes on the pages of its people"; it states the reversal of "a page link is always the person's tap", approach A and the two not chosen, the fourteen decisions, the spec's six calls, and the open items: "Same story" writes no page link; the chip has no "Assumed" mark; moments kept before this build), `docs/OVERVIEW.md` ("A photo starts a story"), `docs/plans/2026-11-18-photo-on-people-pages-device-check.md`, and the spec's status line.

The view reads `card.pagesLine` and `page.stateValue`. It holds no rule.

- [ ] **Step 1: Failing UI tests** (`PhotoCardUITests`):
  - `testThePeopleOfTheStoryStartAdded`: on the session's card, the chips of Maya and Dad have the value "added by this story"; the place chip has "not added"; the line is the story line; Maya's page shows the photo.
  - `testAPersonTakenOffStaysOff`: tap Maya's chip; value "not added"; leave and return; still "not added"; Maya's page does not show the photo.
  - `testAPersonPutBackIsTheOwners`: tap off, tap on; value "added".
  - `testTheLineChangesWhenNoStoryPageIsLeft`: take both people off; the line is "Tap to add. Tap again to take it off."
  - `PeopleGuessUITests.testMovingANameMovesThePhoto` (photo story seed with a guessed name): change the name to "Someone new"; the new person's chip is "added by this story"; the first person's chip is gone or "not added"; Undo puts the first person's chip back to "added by this story".
  - Existing tests that begin with an empty person chip: change the first step as decision 13 says, and list each change.
- [ ] **Step 2:** Run `PhotoCardUITests` and `PeopleGuessUITests`; expected FAIL.
- [ ] **Step 3:** Implement the view change; write the docs. The device check lists: a first story about a new person, then the person's page; a photo taken off, then another moment kept; a name moved to "Someone new" and Undo; a person whose page held the photo before the story; VoiceOver on a chip the story chose; the phone's database after the update (old photo links unchanged).
- [ ] **Step 4:** `swift test`; `PhotoCardUITests`, `PeopleGuessUITests`, `PhotoStoryUITests`, `LandingUITests`, `PhotosUITests`; guards. Expected: all pass.
- [ ] **Step 5:** Commit "The photo card shows the pages the story chose".

### Task 6: Done hides the pages not chosen (kit and app)

**Files:**
- Modify: `Store/Migrations.swift` is NOT touched here: Task 1 adds the column. Modify `Domain/Session.swift` and its record, `Store/SessionRepository.swift`, `Photos/PhotoStory.swift`, `Photos/PhotoStoryReader.swift`, `ios/Lifeline/Screens/Photos/PhotoCardPages.swift`, `PhotoCardViewModel.swift`
- Test: `PhotoStoryTests.swift`, `MigrationsTests.swift` (the column, in Task 1), `PhotoCardUITests.swift`

Task 1 must add to its `v16` block and its tests: `session.photo_pages_done` (decision 15), false on every existing row.

**Interfaces — Produces:**
```swift
extension PhotoStoryCard {
    public var pagesDone: Bool
    /// What the pages part shows. `kept`: pages the owner emptied while the part is done; they stay on screen.
    public func shownPageGroups(keeping kept: Set<EntityID>) -> [PageGroup]   // open: all; done: chosen or kept
    public var showsNoOtherPageSentence: Bool                                   // done, and no page is chosen or kept
}
extension PhotoStoryReader { public func setPagesDone(_ done: Bool, for session: SessionID) throws }
// PhotoCardViewModel: func donePages(), func editPages()
```

- [ ] **Step 1: Failing tests.** Kit: `aNewStoryStartsOpen`; `doneShowsOnlyTheChosenPages`; `doneKeepsAPageTheOwnerJustEmptied`; `doneWithNoChosenPageShowsTheSentence`; `editShowsEveryPageAgain`; `theStateIsStoredForTheStory` (set, build a new reader, read); `aPageTheStoryChoosesAfterDoneShows`. UI (`PhotoCardUITests`): `testDoneHidesTheEmptyChips` (tap "Done": the place chip does not exist, Maya's chip exists, "Edit" exists, the line is gone); `testEditShowsThemAgain`; `testDoneIsRememberedOnTheSessionsPage` (leave, open the session's page: still done); `testAChipEmptiedWhileDoneStaysUntilTheNextDone` (tap Maya while done: value "not added" and the chip exists; "Edit" then "Done": the chip is gone); `testDoneWithNothingChosenSaysSo`; the largest text: "Done" and "Edit" are reachable and at least 44 points high.
- [ ] **Step 2:** Run; expected FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test`; `PhotoCardUITests`, `LandingUITests`, `PhotoStoryUITests`; guards.
- [ ] **Step 5:** Commit "Done hides the pages the owner did not choose; Edit shows them again".

### Task 7: Several photos at one time (app)

**Files:**
- Modify: `ios/Lifeline/Screens/Photos/AddPhotoFlow.swift`, `PhotoShelf.swift`, `ios/Lifeline/Dependencies.swift` (the launch argument)
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoAddProgress.swift` (the two lines, as a pure function)
- Test: `ios/LifelineKit/Tests/LifelineKitTests/PhotoAddProgressTests.swift`, `ios/LifelineUITests/PhotosUITests.swift`

**Interfaces — Produces:**
```swift
public enum PhotoAddProgress {
    public static func line(adding index: Int, of count: Int) -> String      // count 1: today's "Adding the photo…"
    public static func failureLine(failed: Int, lastError: String) -> String? // 0: nil; 1: today's line; more: "{k} photos could not be added."
}
// PhotoShelf: func add(files: [(URL, String?)]) async   — one after the other, in order; a failure does not stop the rest
```

- [ ] **Step 1: Failing tests.** Kit: the table for both functions (1 of 1, 2 of 5, 0 failures, 1 failure, 3 failures). UI (`PhotosUITests`, with `-uiTesting-pickPhotos` and three generated files, one of them not an image): `testSeveralPhotosAreAddedInTheOrderPicked` (two good files on Maya's page: the row gains two thumbs, in order, after the ones it had); `testOneBadPhotoDoesNotStopTheOthers` (the two good ones are added; one error line shows); `testTheFirstPickedPhotoIsTheKeyPhotoOnAnEmptyPage`; `testTheSamePhotoPickedTwiceIsAddedOnce`; every existing test with `-uiTesting-pickPhoto` passes unchanged.
- [ ] **Step 2:** Run; expected FAIL.
- [ ] **Step 3:** Implement (decision 17).
- [ ] **Step 4:** `swift test`; `PhotosUITests`, `EntityPageUITests`, `YouUITests`, `PhotoStoryStartUITests` (its picker must still take one photo); guards. The device check gains: pick five photos, one in iCloud; pick 21 (the picker stops at 20); kill the app while photos are added.
- [ ] **Step 5:** Commit "Add several photos to a page at one time".

## After this plan

- The controller runs the whole UI suite one time and the guards, then asks the owner before a PR. Nothing is pushed without the owner's word.
- The phone branch `phone/photos-contacts` takes this work by a merge, so the owner can check it on the device.
- Not in this plan: page links from "Same story"; a backfill for older photo stories; places, things and the owner's page.
