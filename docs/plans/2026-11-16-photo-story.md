# A Photo Starts a Story Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The person picks one photo, from their Favorites or from a photo already in the app, sees it while they tell its story, and afterwards the photo sits on each memory they keep, with one-tap offers to add it to the pages the story named and to use its date.

**Architecture:** Task 1 adds migration v14 (`session.subject_photo_id`) and makes a session a third home for a photo. Task 2 links the subject photo to a memory in the write that keeps or merges it. Task 3 adds the `photo` date origin and the pure rules for the photo card. Task 4 starts a photo session from the photo viewer and shows the photo on the session screen. Task 5 adds photo access, the Favorites grid and the record bar entry. Task 6 puts the photo card on the landing and on the session's page. Task 7 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, PhotoKit (`PHPhotoLibrary`, `PHAssetCollection`, `PHImageManager`) in the app target only, GRDB 7 (migration v14), Swift Testing, XCUITest.

**Spec:** `docs/specs/2026-11-16-photo-story.md`. Read it whole before Task 1. It builds on S4: `docs/plans/2026-11-16-sections-photos.md` ("Decisions made in this plan") and the "Photos" part of `docs/OVERVIEW.md`.

**Worktree and branch:** `/Users/jakerosen/dev/lifeline/lifeline-photo-story`, branch `photo-story`, cut from `origin/main` at `a1638c3`. Work only there.

## Decisions made in this plan

1. **v14 is one added column.** `session.subject_photo_id`, text, nullable, `references photo(id) on delete set null`, with the index `session_subject_photo`. No table is rebuilt. Before Task 1, the controller confirms that `origin/main` has no `v14` and shows the owner the exact migration.
2. **A photo session is `SessionKind.quick`** with `startedFrom == .photo` and no `subjectEntityID`. `TurnPolicy`, `InterviewerContext` and the interviewer prompt do not change.
3. **Write order at the start:** the photo is stored with no link (`PhotoLibrary.store`), then the recorder inserts the session row with the pointer. A kill between the two leaves a photo with no home; the launch sweep removes it.
4. **The memory link is made at two events only:** when a memory is kept from a candidate of the session, and when a telling of the session is merged into a memory. Both happen inside the existing write transaction. The app does not store "removed from this memory". So a second telling from the same session, merged into the same memory after the person removed the photo, links it again. The spec says "does not add it again"; this plan accepts that one rare case to avoid a new table. The owner sees this in the report.
5. **The S4 cover rule is not changed.** Every link goes through `PhotoRepository.link(_:to:in:)`.
6. **A date from a photo is settled.** `TimeRange.isSettled` is true for origin `photo`. `readsAsSaid` is false for it. The evidence text is `the photo's date, {d MMMM yyyy}` (Gregorian, `en_GB`), for example `the photo's date, 14 July 2019`.
7. **The mark for a date from a photo** is the words "from a photo" in the footnote style, after the date, on the memory page (`memory.range`). Other screens show the date as they show an inferred date today.
8. **The card's rules are one pure function** (`PhotoStory.card`), and one reader that gathers its inputs from the store (`PhotoStoryReader`). The views hold no rule.
9. **PhotoKit sits behind `PhotoPickSource`** in the app target. The kit does not import Photos. Under `-uiTesting`, a scripted source serves `GeneratedPhoto` files; `-uiTesting-photoAccess <full|limited|none|empty>` chooses its state (default `full`).
10. **The app asks with `PHPhotoLibrary.requestAuthorization(for: .readWrite)`.** It never writes to the library. `.readWrite` is the only level that can read an album.
11. **"Tell another" after a photo session** opens the entry for a new photo again (the grid, or the picker without access). After a kill it starts on the tab.
12. **A photo session that starts from the viewer** closes the viewer sheet first, then starts.

## Global Constraints

- The photo, its date and its location are sent nowhere. No new network host. The system can download an iCloud original for the one picked photo (`isNetworkAccessAllowed` on that request only).
- The app asks for photo access only on the first tap of "Tell a story about a photo". Never at launch, never from the viewer path, never from "Add a photo".
- The app reads only the Favorites album or the allowed set, and stores only the picked photo. No scan, no `PHAsset` fetch outside that album.
- A link to a page and a date from a photo come only from a tap. An offer has no "No" button and stores no "declined" state.
- The app never says what is in a photo.
- Copy, exact:
  - Record bar menu: "Tell a story about a photo". Viewer button: "Tell its story".
  - Explanation screen: "Lifeline will ask to see your photos. They stay on this phone. Lifeline shows them only so you can pick one." Button: "Continue".
  - `NSPhotoLibraryUsageDescription`: "Lifeline shows your photos so you can pick one and tell its story. They stay on this phone."
  - Grid headings: "Your favorites", "Photos you allowed". Grid button: "All photos".
  - Opening: "Tell me about this one." Session name in lists and on the bar: "A story about a photo".
  - Card: "This photo goes on each moment you keep." "Remove". "Add to {title}'s page". "Add to your page". "The photo is dated {d MMMM yyyy}. Use that for when this happened?" "Use this date". "Remove the photo from this story".
  - Delete dialog, added sentence: "Its photo goes too."
  - Memory page mark: "from a photo".
  - Progress and errors: the S4 strings ("Adding the photo…", "Could not add this photo: {reason}").
- Accessibility labels for the subject photo use the S4 caption (`PhotoCaption`), never the content: "Photo for this story", with the caption as the value.
- New accessibility identifiers: `home.photoStory`, `photo.tellStory`, `photoAccess.continue`, `favorites.grid`, `favorites.heading`, `favorites.photo`, `favorites.allPhotos`, `session.photo`, `photoCard`, `photoCard.pending`, `photoCard.memory`, `photoCard.removeFromMemory`, `photoCard.addToPage`, `photoCard.useDate`, `photoCard.removeFromStory`. Keep every existing identifier.
- Every control is at least 44 by 44 points. Dynamic Type must not clip. Text colours and styles follow the S4 plan's constraints (`Theme.ink`, `Theme.secondaryText`, `Theme.oliveText`, `Theme.ochreText`; no new colour values; no text on a photo).
- View models do no reads in `init` and expose `isLoaded`, as in S4.
- Kit tests: `cd ios/LifelineKit && swift test`, in full at every task.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`. Each task names its classes. The report gives the verbatim `Executed N tests, with M failures` line for each. The whole UI suite runs once, by the controller, after the final review.
- The guards run before the PR: `python3 .github/scripts/pr_guards.py origin/main`.
- Real TDD: each new test is seen failing first. No assertion is weakened. Tests this plan moves: `MigrationsTests.schemaVersionsOrderByMigrationPosition` (`"v13"` becomes `"v14"`).
- Test photos come from `GeneratedPhoto`. Fixtures are invented (Maya, Dad, "The tree house").
- `ios/Config/Local.xcconfig` is never committed. Commit messages are imperative, one line, with a body when the why is not obvious. No AI attribution lines. Nothing is pushed.
- Docs under `docs/` use ASD-STE100 style.

## Review Focus

1. **Migration with data.** A v13 database with sessions, photos and links migrates to v14 with every row unchanged and every `subject_photo_id` null. Task 1 (`v14OnAPopulatedV13Database`).
2. **A photo that loses its last page while a story still points at it.** It must stay, and still show on the session's page; when the story lets go and nothing else holds it, the row and the file go in one call. Task 1 (`aPhotoAStoryPointsAtSurvivesItsLastUnlink`, `lettingGoOfTheLastHomeDeletesRowAndFile`, `twoStoriesAboutOnePhotoEachHoldIt`).
3. **A kill between the import and the session row.** The next launch removes the photo and nothing else. Task 1 (`aStoredPhotoWithNoHomeGoesAtTheSweep`).
4. **A date tapped from a photo, then more sorting.** Keeping another memory runs the resolver; the tapped date must not move. Task 3 (`theResolverLeavesAPhotoDateAlone`).
5. **Access refused or changed.** Refused, limited, empty Favorites, and access changed between two sessions: each opens the right screen with no error and no second prompt. Task 5 (`testNoAccessOpensThePicker`, `testLimitedAccessShowsWhatWasAllowed`, `testAnEmptyAlbumOpensThePicker`).

---

### Task 1: The session points at its photo (kit)

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/Migrations.swift`, `Domain/Session.swift`, `Store/AppDatabase.swift` (session coding keys), `Session/SessionRecorder.swift`, `Store/PhotoRepository.swift`, `Store/SessionRepository.swift`, `Photos/PhotoLibrary.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/MigrationsTests.swift`, `PhotoRepositoryTests.swift`, `PhotoLibraryTests.swift`

**Interfaces — produces:**
- `Session.subjectPhotoID: PhotoID?` (init parameter `subjectPhotoID: PhotoID? = nil`); `SessionOrigin.photo`.
- `SessionRecorder.start(id:kind:subject:subjectPhoto:startedFrom:)`, with `subjectPhoto: PhotoID? = nil`.
- `PhotoRepository.insert(_ photo: Photo) throws` (no link).
- `PhotoRepository.subjectPhoto(of session: SessionID) throws -> Photo?`
- `PhotoRepository.hasOtherHome(_ photo: PhotoID, than session: SessionID) throws -> Bool`: true when a link exists to an entity, or to a memory that has a span outside that session, or another session points at the photo.
- `PhotoRepository.letGo(of session: SessionID) throws -> Photo?`: sets the pointer to null; when the photo then has no link and no other session, deletes the row and returns it.
- `PhotoLibrary.store(fileAt source: URL, assetLocalID: String?, now: Date = .now) throws -> Photo`: the import of `add` with no link. Same SHA-256 already stored: returns the stored photo, writes a missing file again, adds no link.
- `PhotoLibrary.removeFromStory(_ session: SessionID) throws`: `letGo`, then deletes the file of a returned photo.

Changed rules: `deleteUnlinked` and `unlink` treat a photo as homeless only when it has no link and no `session.subject_photo_id` points at it.

- [ ] **Step 1: Write the failing tests.**

`MigrationsTests`:
```swift
@Test func v14OnAPopulatedV13Database() throws   // migrate to "v13", insert a session, a photo and a link, migrate to "v14"
// #expect: session count, photo count and link count are unchanged; every subject_photo_id is nil;
// #expect: an update that sets subject_photo_id to the photo's id succeeds; one to an unknown id throws.
@Test func deletingAPhotoRowClearsTheSessionsPointer() throws   // #expect(session.subjectPhotoID == nil); the session row remains
```
`PhotoRepositoryTests`:
```swift
@Test func aPhotoAStoryPointsAtSurvivesItsLastUnlink() throws
// photo linked to Maya, session points at it; unlink from Maya returns nil; #expect(photos.photo(id:) != nil)
@Test func deleteUnlinkedKeepsAPhotoAStoryPointsAt() throws      // #expect(try photos.deleteUnlinked().isEmpty)
@Test func lettingGoKeepsAPhotoWithAPage() throws                // letGo returns nil; photo(id:) != nil; subjectPhoto(of:) == nil
@Test func twoStoriesAboutOnePhotoEachHoldIt() throws            // letGo(first) returns nil; subjectPhoto(of: second)?.id == photo.id
@Test func hasOtherHomeIgnoresMemoriesOnlyFromThisSession() throws
// memory A has spans only in the session: false. Add a link to Dad: true. Remove it, add memory B with a span in another session: true.
```
`PhotoLibraryTests`:
```swift
@Test func storeWritesTheFileAndARowWithNoLink() async throws    // file exists; photos(of:) is empty for every subject; row exists
@Test func storingTheSamePhotoTwiceKeepsOneCopy() async throws   // same id back; one .jpg in the folder
@Test func storingRepairsAMissingFile() async throws
@Test func aStoredPhotoWithNoHomeGoesAtTheSweep() async throws   // sweep() == Swept(rows: 1, files: 1)
@Test func lettingGoOfTheLastHomeDeletesRowAndFile() async throws
@Test func aFailedStoreLeavesNoFileAndNoRow() async throws       // writeCopy throws
```
`SessionRecorder` (in its existing test file): `aPhotoSessionRowCarriesItsPhotoFromTheStart` — after `start(subjectPhoto:startedFrom: .photo)`, the fetched row has `subjectPhotoID` and `startedFrom == .photo` before any segment.

- [ ] **Step 2: Run `swift test --filter "v14|Photo|aPhotoSession"`.** Expected: compile failures for the new names.
- [ ] **Step 3: Add the migration, exactly:**
```swift
// v14 (photo story): the photo a session is about. A session is a third home for a photo.
m.registerMigration("v14") { db in
    try db.alter(table: "session") { t in
        t.add(column: "subject_photo_id", .text).references("photo", onDelete: .setNull)
    }
    try db.create(index: "session_subject_photo", on: "session", columns: ["subject_photo_id"])
}
```
- [ ] **Step 4: Implement the interfaces above.** `letGo` and the changed `unlink` each run in one write.
- [ ] **Step 5: Run `swift test`.** Expected: all pass, with `schemaVersionsOrderByMigrationPosition` moved to `"v14"`.
- [ ] **Step 6: Commit** "Store: a session points at the photo it is about (v14)".

### Task 2: A kept memory gets the session's photo (kit)

**Files:**
- Modify: `Store/PhotoRepository.swift`, `Store/MemoryRepository.swift` (the static write of `insert`, static `mergeSpan`, `mergeGroup`)
- Test: `PhotoRepositoryTests.swift`, `MergeActionsTests.swift`, the test file of `CandidateActions`

**Interfaces:**
- Consumes: `session.subject_photo_id` (Task 1); `PhotoRepository.link(_:to:in:)`.
- Produces: `static func PhotoRepository.linkSubjectPhoto(ofSegment segment: SegmentID, to memory: MemoryID, in db: Database) throws`. It finds the segment's session; with a subject photo, it links it to the memory by the S4 rule; with none, it does nothing.

`MemoryRepository.insert` calls it with the first span's segment when `acceptingCandidate` is set. `mergeSpan` and `mergeGroup` call it with the merged span's segment and the target memory.

- [ ] **Step 1: Write the failing tests.**
```swift
@Test func keepingAMemoryFromAPhotoSessionLinksThePhoto() throws
// acceptMemory on a candidate of the photo session; #expect(photos.photos(of: .memory(m.id)).map(\.photo.id) == [photo.id])
@Test func theFirstPhotoOnAMemoryIsItsCover() throws             // role == .cover
@Test func aMemoryThatHasACoverKeepsIt() throws                  // merge into a memory with a cover: new photo is .attached, last
@Test func mergingATellingFromAPhotoSessionLinksThePhotoToTheTarget() throws   // mergeCandidate(into:)
@Test func aGroupMergeLinksThePhotoOnce() throws                 // mergeGroup; exactly one link on the target
@Test func aSessionWithNoPhotoLinksNothing() throws
@Test func aFloatingMemoryGetsNoPhoto() throws                   // insertFloating in a photo session: no link (the person did not tell it)
@Test func aRemovedPhotoStaysRemovedOnALaterRead() throws        // unlink, then fetch memories and the card inputs: still no link
@Test func aFailedKeepLinksNothing() throws                      // the insert throws (bad span): no photo_link row
@Test func separatingATellingLeavesThePhotoOnTheOriginal() throws   // separateTelling: the new memory has no photo
```
- [ ] **Step 2: Run them; expected FAIL** (no link rows).
- [ ] **Step 3: Implement `linkSubjectPhoto` and the three calls**, inside the existing transactions.
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit** "Store: a memory kept from a photo's story holds the photo".

### Task 3: The photo's date and the card's rules (kit)

**Files:**
- Modify: `Domain/TimeRange.swift`
- Create: `Photos/PhotoStory.swift` (the pure rules), `Photos/PhotoStoryReader.swift` (reads the store, applies taps)
- Test: `TimeRangeTests.swift`, the resolver's test file, new `PhotoStoryTests.swift`

**Interfaces — produces:**
```swift
// RangeOrigin gains `case photo`.
public static func TimeRange.fromPhoto(_ date: CivilDate) -> TimeRange   // that day, granularity .day, origin .photo, evidence per decision 6
public var TimeRange.isFromPhoto: Bool

public struct PhotoStoryCard: Sendable, Equatable {
    public struct DateOffer: Sendable, Equatable, Identifiable { public var memory: Memory; public var date: CivilDate; public var id: MemoryID { memory.id } }
    public var photo: Photo
    public var hasPendingMoments: Bool      // a pending memory candidate or a pending segment in the session
    public var memories: [Memory]           // memories of the session that hold the photo, in telling order
    public var pageOffers: [Entity]         // linked to those memories, not holding the photo, not hidden from browsing; a page kept from the AI is offered; owner first, then by title
    public var dateOffers: [DateOffer]
    public var hasOtherHome: Bool           // PhotoRepository.hasOtherHome
}
public enum PhotoStory {
    /// True when the memory is unplaced, or `date` is before `earliest` or after `latest`. False with no date.
    public static func offersDate(_ date: CivilDate?, for range: TimeRange) -> Bool
    public static func card(photo: Photo, sessionMemories: [Memory], holding: Set<MemoryID>, linked: [MemoryID: [Entity]],
                            pagesWithPhoto: Set<EntityID>, ownerEntity: EntityID?, hasPendingMoments: Bool, hasOtherHome: Bool) -> PhotoStoryCard
}
public struct PhotoStoryReader: Sendable {
    public init(store: ExtractionStore)
    public func card(for session: SessionID) throws -> PhotoStoryCard?      // nil when the session has no subject photo
    public func addToPage(_ photo: PhotoID, _ entity: EntityID) throws      // PhotoRepository.link
    public func useDate(_ offer: PhotoStoryCard.DateOffer) throws           // MemoryRepository.updateRange(.fromPhoto), then the chapter range refresh that updateRange already does
}
```
`pageOffers` covers every entity type. Date offers are made only for memories in `memories`. A half-open range (only `earliest` or only `latest`) offers the date when it is on the open side's wrong side or the range is not dated: treat a missing edge as unbounded.

- [ ] **Step 1: Write the failing tests.**
```swift
@Test func aPhotoDateIsSettledAndDoesNotReadAsSaid()
// let r = TimeRange.fromPhoto(CivilDate(2019, 7, 14)); #expect(r.isSettled); #expect(!r.readsAsSaid); #expect(r.isFromPhoto)
// #expect(r.earliest == r.latest); #expect(r.granularity == .day); #expect(r.evidenceText == "the photo's date, 14 July 2019")
@Test func aPhotoOriginSurvivesTheDatabase() throws              // updateRange, fetch: origin == .photo
@Test func theResolverLeavesAPhotoDateAlone() throws
// memory with an anchor that would place it in 1998; useDate 14 July 2019; ResolverRunner(store:).run(); range unchanged
@Test func noWhenQuestionTargetsAMemoryDatedFromAPhoto() throws   // same assertion the suite makes for `.confirmed`
@Test func aStatedDateReplacesAPhotoDate() throws                // TimeRange.stated(year: 2018) over it: origin == .stated
@Test func offersDate() // table:
// unplaced → true; photo date inside earliest…latest → false; one day before earliest → true; one day after latest → true;
// equal to earliest → false; nil date → false; range already .fromPhoto(same day) → false; only earliest set, date after it → false
@Test func theCardListsWhatHoldsThePhoto()                       // memories only those in `holding`, in input order
@Test func aPageThatHoldsThePhotoIsNotOffered()
@Test func aPageIsOfferedOnceWhenTwoMemoriesNameIt()
@Test func theOwnersPageLeadsTheOffers()
@Test func aHiddenPageIsNotOffered()
@Test func aMemoryWithoutThePhotoGetsNoDateOffer()
@Test func aPhotoWithNoDateOffersNoDate()
@Test func theReaderGivesNoCardForAnOrdinarySession() throws     // nil
@Test func theReaderSeesAMemoryKeptLater() throws                // card before keep: memories empty, hasPendingMoments; after keep: one memory
@Test func addToPageUsesTheCoverRule() throws                    // Dad has no photo: role .cover; Maya has one: .attached
```
- [ ] **Step 2: Run them; expected compile FAIL.**
- [ ] **Step 3: Implement.** In `TimeRange`: `isSettled` adds `.photo`; `readsAsSaid` returns false when `isFromPhoto`.
- [ ] **Step 4: Run `swift test`.** Expected: all pass. Fix any `switch` over `RangeOrigin` the compiler reports; a `photo` range displays as an inferred one does unless decision 7 says otherwise.
- [ ] **Step 5: Commit** "Kit: a date can come from a photo, and the rules of the photo card".

### Task 4: A photo session from the viewer, with the photo on screen (app)

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Prompts/OpeningPrompt.swift`, `ios/Lifeline/Dependencies.swift`, `Screens/Home/HomeViewModel.swift`, `Screens/Session/SessionViewModel.swift`, `Screens/Session/SessionScreen.swift`, `Screens/Photos/PhotoViewer.swift`, the Sessions list row and the record bar label for a running session, `Screens/Memory/` (the "from a photo" mark), `ios/Lifeline/UITestSeed.swift`
- Create: `Screens/Session/SessionPhoto.swift` (the photo block on the session screen)
- Test: `OpeningChooser` tests in the kit; new `ios/LifelineUITests/PhotoStoryUITests.swift`

**Interfaces:**
- Consumes: `SessionRecorder.start(…subjectPhoto:…)`, `PhotoImageView` (S4), `PhotoCaption`.
- Produces: `OpeningPrompt.photo(PhotoID, text: String)` with `logID == "photo"`; `OpeningChooser.choose(photo: PhotoID? = nil, subject:…)` — with a photo, `main` is `.photo(id, text: "Tell me about this one.")` and the alternates are the first three scenes; `Dependencies.opening(photo:)`; `HomeViewModel.startPhotoSession(_ photo: Photo) async` (same guards and microphone path as `startSession`); `SessionViewModel.init(deps:kind:subject:photo:)` and `let photo: Photo?`; `HomeViewModel.lastWasPhoto`.

`ScriptedVoiceSession` and the scripted extraction already produce segments and candidates under `-uiTesting`; the photo seed is `launchWithPhotos()`.

- [ ] **Step 1: Write the failing tests.**

Kit:
```swift
@Test func aPhotoOpensWithTellMeAboutThisOne()
// let o = OpeningChooser.choose(photo: id, curiosity: [openItem], bank: bank, lastUsed: [:], now: now)
// #expect(o.main == .photo(id, text: "Tell me about this one.")); #expect(o.main.logID == "photo")
// #expect(o.alternates.count == 3); no alternate is a curiosity item
@Test func aPhotoWinsOverASubject()                              // both given: main is .photo
```
UI (`PhotoStoryUITests`, launch `launchWithPhotos()`):
- `testTellItsStoryStartsASessionWithThePhotoOnScreen`: open Maya, tap the cover, tap `photo.tellStory` (label "Tell its story"); `photo.viewer` is gone; `session.photo` exists with label "Photo for this story" and value "taken 14 June 2012"; the opening text is "Tell me about this one."; `session.photo.frame.maxY` is less than the opening's `frame.minY`.
- `testThePhotoStaysWhileThePersonTalks`: after the scripted segments appear, `session.photo` still exists and is hittable after scrolling to the top.
- `testAPhotoSessionAsksNothingAfterItsOpening` (with `-uiTesting-speaks -uiTesting-followUps`): no interviewer turn other than the opening appears before Finish.
- `testThePhotoKeepsItsPage`: after Finish and "Done for now", Maya's page still has `photo.header`.
- `testTheSessionsListNamesAPhotoStory`: Sessions shows "A story about a photo" for it.
- `testTheSessionScreenHoldsAtTheLargestText`: at accessibility size XXXL, `session.photo`, the opening and the Finish control are each reachable by `reveal`, and each control is at least 44 points high.
- `testADateFromAPhotoSaysSo` (seed: `-uiTesting-seedPhotos` gains one memory, "The beach", dated with `TimeRange.fromPhoto(14 June 2012)`): its page's `memory.range` contains "14 June 2012" and "from a photo".

- [ ] **Step 2: Run the kit filter and `-only-testing:LifelineUITests/PhotoStoryUITests`; expected FAIL.**
- [ ] **Step 3: Implement.** `SessionViewModel.start` passes `subjectPhoto: photo?.id` and `startedFrom: .photo`. The viewer's button calls its `onTellStory` closure after `dismiss()`. `sessionEnded` sets `lastWasPhoto`. For now "Tell another" after a photo session starts a tab session; Task 5 changes it.
- [ ] **Step 4: Run** `swift test`, then `PhotoStoryUITests`, `PhotosUITests` and `ShellUITests`. Expected: all pass.
- [ ] **Step 5: Commit** "A photo in the app starts its own story".

### Task 5: Photo access, the Favorites grid and the record bar entry (app)

**Files:**
- Modify: `ios/project.yml` (`NSPhotoLibraryUsageDescription`), `ios/Lifeline/Dependencies.swift`, `Screens/Shell/RecordBar.swift`, `Screens/Home/HomeViewModel.swift`, `Screens/Photos/AddPhotoFlow.swift` (share the picker path; "Add a photo" behaviour unchanged)
- Create: `ios/Lifeline/Photos/PhotoPickSource.swift` (protocol and value types), `Photos/LibraryPhotoPickSource.swift` (PhotoKit), `Photos/ScriptedPhotoPickSource.swift` (tests), `Screens/Photos/PhotoAccessScreen.swift`, `Screens/Photos/FavoritesGridScreen.swift`, `Screens/Photos/PhotoStoryStartViewModel.swift`
- Test: new `ios/LifelineUITests/PhotoStoryStartUITests.swift`; a unit test target is not available for the app, so `PhotoStoryStart.route` lives in the kit (`Photos/PhotoStoryStart.swift`) with tests in `PhotoStoryStartTests.swift`

**Interfaces — produces:**
```swift
// Kit, pure:
public enum PhotoAccess: Sendable, Equatable { case notAsked, full, limited, none }
public enum PhotoStoryStart: Sendable, Equatable {
    case explain            // .notAsked: the explanation screen, then the system prompt
    case grid(heading: String)
    case picker
    public static func route(access: PhotoAccess, photoCount: Int) -> PhotoStoryStart
}
// App:
struct LibraryPhoto: Identifiable, Sendable, Equatable { let id: String }      // the asset's local identifier
protocol PhotoPickSource: Sendable {
    func access() -> PhotoAccess
    func requestAccess() async -> PhotoAccess
    func photos() async -> [LibraryPhoto]                       // Favorites (full) or the allowed set (limited), newest first
    func thumbnail(for photo: LibraryPhoto, side: CGFloat) async -> UIImage?
    func file(for photo: LibraryPhoto) async throws -> URL      // a temporary copy of the original, for PhotoLibrary.store
}
```
`PhotoStoryStartViewModel.pick(_:)` shows "Adding the photo…", calls `file(for:)`, then `PhotoLibrary.store(fileAt:assetLocalID:)`, removes the temporary copy, then `home.startPhotoSession`. A failure shows the S4 error line and starts nothing. The picker path uses the S4 picked-copy code and the same `store`.

- [ ] **Step 1: Write the failing tests.**

Kit:
```swift
@Test func route() // table:
// (.notAsked, 0) → .explain; (.full, 3) → .grid(heading: "Your favorites"); (.limited, 2) → .grid(heading: "Photos you allowed");
// (.full, 0) → .picker; (.limited, 0) → .picker; (.none, 5) → .picker
```
UI (`PhotoStoryStartUITests`; the scripted source serves three generated photos; `-uiTesting-pickPhoto` serves the picker path):
- `testTheEntryIsInTheRecordBarMenuOnEveryTab`: on each of the five tabs the menu holds `home.photoStory`, labeled "Tell a story about a photo", below "Settle in".
- `testTheFirstTapExplainsThenShowsFavorites` (`-uiTesting-photoAccess notAsked`): the explanation copy is on screen with `photoAccess.continue`; after the tap, `favorites.heading` reads "Your favorites" and `favorites.photo` count is 3, newest first.
- `testTheExplanationShowsOnce`: a second start goes straight to the grid.
- `testATapOnAFavoriteStartsItsStory`: tap the first `favorites.photo`; `session.photo` exists; the opening is "Tell me about this one."; no confirmation appears.
- `testLimitedAccessShowsWhatWasAllowed`: heading "Photos you allowed"; the text "Your favorites" does not exist.
- `testNoAccessOpensThePicker` and `testAnEmptyAlbumOpensThePicker`: no grid, no error text; the session starts with the `-uiTesting-pickPhoto` file.
- `testAllPhotosOpensThePicker`: `favorites.allPhotos` (label "All photos") starts a session with the picked file.
- `testAnUnreadablePhotoStartsNoSession` (`-uiTesting-pickPhoto` the `not-a-photo.jpg` fixture): the S4 error text shows; no session screen; Sessions has no new row.
- `testTwoStoriesFromTheSameFavorite`: two stories from the same favorite; each session's page shows `photoCard`'s photo after Task 6 (in this task: each session screen shows `session.photo`). The one-copy rule itself is proved in the kit (`storingTheSamePhotoTwiceKeepsOneCopy`).
- `testTellAnotherOpensTheGridAgain`: on the first-session landing, "Tell another" shows `favorites.grid`.
- `testTheGridHoldsAtTheLargestText`: heading, three photos and "All photos" are reachable; "All photos" is at least 44 points high.
- `testAddAPhotoStillAsksForNoAccess` (`-uiTesting-photoAccess notAsked`): "Add a photo" on Maya's page adds the picked file and never shows the explanation screen.

- [ ] **Step 2: Run them; expected FAIL.**
- [ ] **Step 3: Implement.** `LibraryPhotoPickSource`: `PHPhotoLibrary.authorizationStatus(for: .readWrite)` maps to `PhotoAccess`; full access fetches `PHAssetCollection` subtype `.smartAlbumFavorites`, images only, sorted by `creationDate` descending; limited access fetches all allowed image assets the same way; `file(for:)` uses `PHAssetResourceManager.writeData` for the photo resource into the temporary directory with `isNetworkAccessAllowed = true`. The grid loads thumbnails off the main thread and decodes each once.
- [ ] **Step 4: Run** `swift test`, then `PhotoStoryStartUITests`, `PhotoStoryUITests`, `PhotosUITests`, `ShellUITests`. Expected: all pass. Run the guards script.
- [ ] **Step 5: Commit** "Tell a story about a photo: access, Favorites and the record bar entry".

### Task 6: The photo card on the landing and the session's page (app)

**Files:**
- Create: `Screens/Photos/PhotoCard.swift`, `Screens/Photos/PhotoCardViewModel.swift`
- Modify: `Screens/Landing/LandingScreen.swift`, `LandingViewModel.swift`, `Screens/SessionDetail/` (the screen and its view model), the session delete dialogs on both screens, `ios/Lifeline/UITestSeed.swift`
- Test: new `ios/LifelineUITests/PhotoCardUITests.swift`; kit test for the dialog sentence in `PhotoStoryTests.swift`

**Interfaces:**
- Consumes: `PhotoStoryReader`, `PhotoStoryCard`, `PhotoLibrary.remove(_:from:)`, `PhotoLibrary.removeFromStory(_:)`.
- Produces: `PhotoCardViewModel(session: SessionID, deps:, showsRemoveFromStory: Bool)` with `refresh()`, `addToPage(_:)`, `useDate(_:)`, `removeFromMemory(_:)`, `removeFromStory()`; `PhotoStory.deleteSentence(card: PhotoStoryCard?) -> String?` returning "Its photo goes too." when the card exists and `hasOtherHome` is false.

The card sits on the landing after the moment rows and before "Before you go". The landing's existing one-second poll also refreshes the card. On the session's page it sits at the top. A new seed, `-uiTesting-seedPhotoStory`, adds to the photo seed one landed photo session about a generated photo dated 14 June 2012, with two kept memories: "The beach" (unplaced, names Maya and Dad) and "The drive home" (stated 2012, names Dad). Maya's page holds the photo already; Dad's does not.

- [ ] **Step 1: Write the failing tests.**

Kit: `theDeleteSentence` — nil card → nil; `hasOtherHome` true → nil; false → "Its photo goes too."

UI (`PhotoCardUITests`):
- `testTheLandingSaysThePhotoGoesOnWhatYouKeep`: a live photo session from the viewer, Finish; `photoCard` exists with `photoCard.pending` reading "This photo goes on each moment you keep."; "Done for now" is still the first prominent choice and closes the landing with no tap on the card.
- `testAKeptMomentHoldsThePhoto`: from that landing, "Review these moments", keep the first card; back on the landing the card lists that memory's title under `photoCard.memory`; the memory's page shows the photo.
- `testTheCardOnTheSessionsPage` (seed): the card lists "The beach" and "The drive home"; `photoCard.addToPage` has exactly one button, "Add to Dad's page"; none for Maya.
- `testAddToAPagePutsThePhotoThere`: tap it; the button goes; Dad's page shows `photo.header` (his first photo is his cover).
- `testTheDateIsOfferedOnlyWhereItHelps`: one `photoCard.useDate` block, for "The beach", with the text "The photo is dated 14 June 2012. Use that for when this happened?"; none for "The drive home" (2012 contains the date).
- `testUseThisDateDatesTheMemory`: tap "Use this date"; the offer goes; "The beach" page's `memory.range` contains "14 June 2012" and "from a photo".
- `testRemoveTakesThePhotoOffOneMemory`: `photoCard.removeFromMemory` on "The drive home"; its page has no photo; "The beach" keeps it; the card no longer lists "The drive home" and offers nothing for it.
- `testRemoveThePhotoFromThisStory`: `photoCard.removeFromStory` exists on the session's page and not on a landing; after the tap the card is gone and "The beach" still shows the photo.
- `testDeletingAStorySaysWhenItsPhotoGoes`: a second seeded photo session whose photo has no other home: the delete dialog's message ends with "Its photo goes too."; the first seeded session's dialog does not contain it.
- `testAnOrdinarySessionHasNoCard`: a tab session's landing and page have no `photoCard`.
- `testTheCardHoldsAtTheLargestText`: every card control is reachable and at least 44 points high.

- [ ] **Step 2: Run them; expected FAIL.**
- [ ] **Step 3: Implement.** Errors use `PhotoErrorSlot`. After each action the card refreshes from the store.
- [ ] **Step 4: Run** `swift test`, then `PhotoCardUITests`, `PhotoStoryUITests`, `LandingUITests`, `PhotosUITests`. Expected: all pass.
- [ ] **Step 5: Commit** "The photo card: where a story's photo went, and what it can still do".

### Task 7: Docs, screenshots and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` (the shape of the app; "Photos"; move Phase 1.5 out of "Designed, not built"; the data posture line on photo access; "Next"), `docs/DECISIONS.md`, `CLAUDE.md` only if a non-negotiable's wording now misstates photo access
- Create: `docs/plans/2026-11-16-photo-story-device-check.md`, `docs/screenshots/photo-story/`

- [ ] **Step 1: `docs/DECISIONS.md`**, new entry "2026-11-16 · A photo starts a story; the app asks to see Favorites". It must state: the reversal of S4's "no photo-library permission" rule and the owner's reason; the three homes of a photo; open and listen; tap-only offers; decision 4 of this plan (the re-link case) as an open item for the owner; every ruling made while building.
- [ ] **Step 2: `docs/OVERVIEW.md`**, in ASD-STE100 style.
- [ ] **Step 3: The device checklist**, numbered, each with what to do and what must be true: the system prompt answered Full, Limited and Don't Allow (three fresh installs); access changed in Settings between two stories; a Favorites album with an iCloud-only photo ("Adding the photo…" shows, then the session starts); a scanned print (its date is offered, and the person can ignore it); the photo on screen while the app speaks the opening; VoiceOver on the grid and the card; the largest text size on the session screen; a kill during a photo session, then the resumed landing with its card; export, delete the app, restore: the story still shows its photo.
- [ ] **Step 4: Screenshots** with invented data: the explanation screen, the grid, the session with its photo, the landing card, the session page's card, a memory dated from a photo.
- [ ] **Step 5: Commit** "Docs: a photo starts a story".

## After this plan

- Follow-up questions about a photo, and "Settle in" with a photo.
- "Who's this?" naming, clusters, the photo's place as an offer.
- Opening "Add a photo" on Favorites.
