# Timeline chapters (S6c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chapter becomes a name with optional stated years and said members. The person can tag a moment, open a chapter, rename it, say when it was, remove it, and see every chapter on one life map.

**Architecture:** The kit stops writing a chapter's range from its members; `chapter.range` holds stated years only, and the resolver computes the member span for each run. One new action type, `ChapterActions`, owns rename, say-when, remove with undo, and add-to-chapter. One pure function, `LifeMap`, lays out the map. The app adds three sheets (add to a chapter, the chapter's sheet, the life map) and makes the tag a button.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), GRDB/SQLite, Swift Testing in `ios/LifelineKit`, XCUITest in `ios/LifelineUITests`, xcodegen.

**Spec:** `docs/specs/2026-11-16-timeline.md`, sections "The model of a chapter", "Tags", "The life map", "The chapter's sheet", "Data" and "Edge cases". Mock-ups: `docs/design/TL_LifeMap.dc.html`, `docs/design/TL_ChapterSheet.dc.html`. This plan builds on S6a (`docs/plans/2026-11-16-timeline-spine.md`).

## Global Constraints

- **No migration.** `memory.chapter_id` is the one tag for a moment. `story.chapter_id` stays in the schema; the Timeline does not read it.
- `chapter.range` holds stated years only. No code may write a member span to it. The member span is never shown as the chapter's dates.
- A chapter has stated years only when its stored range is placed and its origin is `stated` or `confirmed`. A stored range with origin `derived` or `inferred` is from before this change and counts as no stated years.
- A date overlap is not a claim about a moment. The app must not tag a moment because its date falls in a chapter's years.
- The Timeline never groups moments under a chapter. "Untitled chapter" must not show on the Timeline.
- Exact copy: the life map's title is "Chapters". Its first line is "Every stretch of your life you have named. Tap one to see its moments." With no chapters the sheet shows only "A chapter is a name you gave to a stretch of your life." The section for chapters without stated years is "Not placed in time yet", and its button is "Say when". The chapter's sheet has "Rename", "Say when it was" and "Remove chapter…". The remove question says "Removing a chapter never removes a memory. Its moments stay on your timeline." The notice is "Removed “{name}”." with "Undo", for 6 seconds. The row menu item is "Add to a chapter…".
- No count of what is missing shows anywhere. No empty frame shows.
- PRINCIPLES 1: a tag shows only what the person said, and the app does not correct a said member whose date is outside the chapter's stated years. PRINCIPLES 5: a chapter shows no years until the person states them. PRINCIPLES 9: no empty chapter shows on the Timeline.
- Each write that touches more than one row is one transaction (a kill mid-operation must not leave half a change).
- Docs under `docs/` use ASD-STE100 style. Fixtures are invented. Commit after each task, imperative one-line message. No AI attribution in commits or PR text.
- UI tests: per task, run only the classes the task names. Run the whole UI suite once, in Task 9. Use the simulator id given at execution time in every `xcodebuild -destination`.

## Builder's defaults the owner can overrule

Read these before Task 1. Each is a choice the spec leaves open.

1. **Where the life map opens from.** The spec opens it from the pinned card (S6b), which does not exist yet. Until S6b, the Timeline's "…" menu (`timeline.more`) has an item "Chapters" (`timeline.chapters`). S6b can keep or remove it.
2. **A chapter with no name that has said members.** It shows no tag on the Timeline (as today). On the life map it shows as "No name yet" so the person can name or remove it. Without this, no action reaches it.
3. **"Take out of “{name}”" in the row menu.** A tagged moment's menu has this item. The spec gives no way to undo a wrong tag except to remove the whole chapter.
4. **Rename to a name another chapter has.** Refused. The sheet says "You already have a chapter with this name." Two chapters are never merged by a rename.
5. **Rename to an empty name.** Refused; Save is disabled. A chapter loses its name only when it is removed.
6. **Existing derived ranges stay in the database.** No write clears them. They are ignored by rule (Global Constraints). "Say when it was" replaces one with a stated range.
7. **The prune keeps a chapter that a story points at.** `deleteEmptyUntitled` keeps its story guard, so the launch repair's behaviour changes in one way only: a chapter with stated years is never pruned.
8. **Undo restores only what is still free.** Undo of a removal puts the tag back on a member only if that memory still exists and has no chapter. It does not take a moment from a chapter the person chose in the meantime.
9. **Said members in the chapter's sheet are text rows.** A tap on one does nothing in this PR.
10. **The extractor's context packet** sends a chapter's stated years, or no years. It no longer sends a member span as the chapter's dates.

## Review Focus

1. **A chapter whose members' dates change after this PR.** The stored range must not move. A person who said "2008 to 2012" must still see that after a member is re-dated. Test in Task 2.
2. **Undo after the world changed.** Remove a chapter, then delete one member or tag it elsewhere inside the 6 seconds, then Undo. The chapter comes back; the app must not crash or steal the tag. Test in Task 4.
3. **A phrase anchored to a chapter with no stated years** ("during the Boston years"). The moment must still be placed from the members' span, as before. Test in Task 3.
4. **A said member dated outside the stated years, and a dated moment inside them with no tag.** The first shows its tag. The second shows none. Tests in Tasks 5 and 8.
5. **Thirty chapters, one with no end, one before the birth year.** The life map must order them, scroll, and start its axis at the earliest year. Test in Task 6.

## File structure

| File | Responsibility |
| --- | --- |
| `ios/LifelineKit/Sources/LifelineKit/Domain/Chapter.swift` (modify) | `statedYears`, `anchorRange(members:)` |
| `ios/LifelineKit/Sources/LifelineKit/Domain/LifeMap.swift` (create) | Pure layout of the life map |
| `ios/LifelineKit/Sources/LifelineKit/Confirmation/ChapterActions.swift` (create) | Rename, say when, remove, undo, add, take out |
| `ios/LifelineKit/Sources/LifelineKit/Confirmation/ChapterReceipt.swift` (create) | What a removal took, for undo |
| `ios/LifelineKit/Sources/LifelineKit/Store/ChapterRepository.swift` (modify) | `rename`, `remove`, `restore`, prune rule |
| `ios/LifelineKit/Sources/LifelineKit/Store/MemoryRepository.swift`, `Confirmation/CandidateActions.swift`, `Confirmation/MergeActions.swift`, `Resolution/ResolverRunner.swift`, `Extraction/ContextPacket.swift` (modify) | Stop writing and reading member spans as chapter dates |
| `ios/Lifeline/Screens/Chapters/AddToChapterSheet.swift` (create) | Pick a chapter or name a new one |
| `ios/Lifeline/Screens/Chapters/ChapterSheet.swift`, `ChapterSheetViewModel.swift` (create) | The chapter's sheet |
| `ios/Lifeline/Screens/Chapters/LifeMapSheet.swift`, `LifeMapViewModel.swift`, `LifeMapRow.swift` (create) | The life map |
| `ios/Lifeline/Screens/Timeline/ChapterTag.swift`, `MemoryRowView.swift`, `TimelineScreen.swift`, `TimelineViewModel.swift` (modify) | Tag as a button, menu items, sheets, notice |
| `ios/LifelineUITests/ChaptersUITests.swift` (create) | UI tests |

---

### Task 1: Stated years on a chapter

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Domain/Chapter.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/ChapterStatedYearsTests.swift` (create)

**Interfaces:**
- Produces: `Chapter.statedYears: TimeRange?`; `Chapter.anchorRange(members: [TimeRange]) -> TimeRange`; `Chapter.name: String?` (the trimmed title, nil when empty).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aStatedRangeIsTheChaptersYears() {
    let c = Chapter(id: .init(), title: "Maple Street", range: .stated(between: 1998, and: 2001), order: 0)
    #expect(c.statedYears?.displayText == "1998–2001")
}
@Test func aConfirmedRangeIsTheChaptersYears() {
    let c = Chapter(id: .init(), title: "A", range: .year(2003, origin: .confirmed, evidence: nil), order: 0)
    #expect(c.statedYears != nil)
}
@Test(arguments: [RangeOrigin.derived, .inferred]) func aRangeFromBeforeThisChangeIsNotStated(origin: RangeOrigin) {
    let c = Chapter(id: .init(), title: "A", range: .year(2003, origin: origin, evidence: nil), order: 0)
    #expect(c.statedYears == nil)
}
@Test func anUnplacedChapterHasNoStatedYears() {
    #expect(Chapter(id: .init(), title: "A", range: .unplaced, order: 0).statedYears == nil)
}
@Test func theAnchorRangeIsTheStatedYearsWhenThereAreAny() {
    let c = Chapter(id: .init(), title: "A", range: .stated(between: 2008, and: 2012), order: 0)
    #expect(c.anchorRange(members: [.stated(year: 1990)]).earliest?.year == 2008)
}
@Test func theAnchorRangeIsTheMemberSpanWhenNothingIsStated() {
    let c = Chapter(id: .init(), title: "A", range: .year(1970, origin: .derived, evidence: nil), order: 0)
    let r = c.anchorRange(members: [.stated(year: 1998), .stated(year: 2001)])
    #expect(r.earliest?.year == 1998 && r.latest?.year == 2001)
    #expect(c.anchorRange(members: []).isPlaced == false)
}
@Test func theNameIsTheTrimmedTitleOrNothing() {
    #expect(Chapter(id: .init(), title: "  Maple Street ", range: .unplaced, order: 0).name == "Maple Street")
    #expect(Chapter(id: .init(), title: "  ", range: .unplaced, order: 0).name == nil)
    #expect(Chapter(id: .init(), title: nil, range: .unplaced, order: 0).name == nil)
}
```

Use the exact text `TimeRange.displayText` gives for 1998 to 2001 in the first test; read it from `TimeRangeTests` if it is not "1998–2001".

- [ ] **Step 2: Run** `swift test --filter ChapterStatedYearsTests` in `ios/LifelineKit`. Expected: does not compile (`statedYears` is not defined).
- [ ] **Step 3: Implement** the three members as an extension in `Chapter.swift`. `anchorRange` uses `ChapterRepository.span(over:)` for the member span. Change the type's doc comment: its range holds stated years only.
- [ ] **Step 4: Run** the filter again. Expected: 7 tests pass (8 cases).
- [ ] **Step 5: Commit** `Chapter: stated years, a name, and the range an anchor reads`.

### Task 2: Nothing writes a member span to a chapter

**Files:**
- Modify: `Confirmation/CandidateActions.swift` (remove `chapterRangeFromMembers`; `assign(memory:toChapter:)` keeps the prune), `Confirmation/MergeActions.swift:101,126`, `Store/MemoryRepository.swift` (remove `refreshChapterRange` and its two calls in `setKind` and `undoKind`), `Resolution/ResolverRunner.swift:89-94` (remove the block "Chapters follow their members"), `Extraction/ContextPacket.swift:122`, `Store/ChapterRepository.swift` (`deleteEmptyUntitled`)
- Test: `ChapterRangeIsStatedTests.swift` (create); change the tests named below.

**Interfaces:**
- Consumes: `Chapter.statedYears` (Task 1).
- Produces: `ChapterRepository.deleteEmptyUntitled()` keeps a chapter that has stated years.

- [ ] **Step 1: Write the failing tests** in `ChapterRangeIsStatedTests.swift`, with the `Env` pattern of `HintActionsTests`:

  - `assigningAMemberDoesNotDateTheChapter`: make a chapter, assign a moment stated 1998. Expect `chapter.range == .unplaced`.
  - `aStatedRangeSurvivesAMemberThatMoves` (Review Focus 1): `setRange(id, .stated(between: 2008, and: 2012))`, assign a moment stated 1990, then `updateRange` that moment to 2020, then `ResolverRunner(store:).run()`. Expect `chapter.range` equal to the stated range.
  - `aKindChangeDoesNotTouchTheChaptersRange`: stated range 2008 to 2012, one member; `actions.setKind(member, .fact)` then `.event`. Expect the range unchanged after each.
  - `aMergeDoesNotTouchTheChaptersRange`: as `MergeActionsTests` line 105 sets up; expect the chapter's range unchanged.
  - `thePruneKeepsAnUntitledChapterWithStatedYears`: `insertChapter(title: nil)`, `setRange` stated 2001. `deleteEmptyUntitled()` returns 0.
  - `thePruneStillRemovesAnUntitledChapterWithADerivedRange`: `insertChapter(title: nil)`, `setRange(.year(2001, origin: .derived, evidence: nil))`. Returns 1.
  - `theContextPacketSendsStatedYearsOnly`: build a packet with one chapter `.year(2011, origin: .derived, evidence: nil)` and one `.stated(year: 2011)`. Expect `rangeText == nil` for the first and `"2011"` for the second.

- [ ] **Step 2: Run** `swift test --filter ChapterRangeIsStatedTests`. Expected: the first, second, third, fifth and seventh fail on their expectations.
- [ ] **Step 3: Make the changes** listed under Files. In `deleteEmptyUntitled`, add to the SQL: the chapter's `origin` column is null or is not `stated` and not `confirmed` (read the range's column names from `Migrations.swift`).
- [ ] **Step 4: Change the existing tests that assert the old rule.** These assert that a chapter's range follows its members. Each must now assert that the range does not change, or must move to Task 3's resolver tests where it tests anchoring. Do not delete a test.
  - `ResolverRunnerTests.swift:121-124` ("the chapter follows its member")
  - `MemoryKindColumnTests.swift:112-123` and `:145-152`
  - `ChapterRepositoryTests.swift:74`
  - `HintActionsTests.swift:86-88`
  - `ContextPacketTests.swift:55-61` (use a stated range)
- [ ] **Step 5: Run** `swift test`. Expected: all pass, except the known flake `ExtractionQueueTests.drainGivesUpAtItsDeadline`, which passes on a rerun.
- [ ] **Step 6: Commit** `A chapter's range holds stated years only`.

### Task 3: The resolver reads a chapter's anchor range

**Files:**
- Modify: `Resolution/ResolverRunner.swift` (`input(...)`)
- Test: `ResolverRunnerTests.swift`

**Interfaces:**
- Consumes: `Chapter.anchorRange(members:)`.
- Produces: no new name. `ResolverInput.chapters` carries copies whose `range` is the anchor range for that run. `Resolver` does not change.

- [ ] **Step 1: Write the failing tests**
  - `aChapterWithNoStatedYearsAnchorsFromItsMembers` (Review Focus 3): chapter "The Boston years", two members stated 2008 and 2012, a third memory with a `during` anchor whose target text is "The Boston years". After `run()`, the third memory's range is inside 2008 to 2012, and `chapter.range == .unplaced`.
  - `aChapterWithStatedYearsAnchorsFromThem`: the same, with `setRange` stated 1995 to 1996. The third memory is placed inside 1995 to 1996.
  - `aFactMemberDoesNotCountInTheAnchorRange`: one member is a fact stated 1970. The span ignores it (use `store.memories.moments(inChapter:)`).
- [ ] **Step 2: Run** `swift test --filter ResolverRunnerTests`. Expected: the first fails (the chapter has no range, so the anchor does not resolve).
- [ ] **Step 3: Implement.** In `input(...)`, map each chapter to a copy with `range = chapter.anchorRange(members: moments(inChapter:).map(\.range))`. Compute it on every call, so the second resolve pass sees ranges the first pass placed.
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `The resolver computes a chapter's member span for each run`.

### Task 4: Chapter actions

**Files:**
- Create: `Confirmation/ChapterActions.swift`, `Confirmation/ChapterReceipt.swift`
- Modify: `Store/ChapterRepository.swift`, `Confirmation/CandidateActions.swift` (`acceptHint`'s chapter case calls `ChapterActions.add(_:toChapterNamed:)`)
- Test: `ChapterActionsTests.swift` (create)

**Interfaces:**
- Produces:

```swift
public struct ChapterReceipt: Sendable, Equatable {
    public let chapter: Chapter
    public let members: [MemoryID]
    public let stories: [StoryID]
}
public struct ChapterActions: Sendable {
    public enum RenameResult: Equatable, Sendable { case renamed, empty, taken }
    public init(store: ExtractionStore)
    public func rename(_ id: ChapterID, to title: String) throws -> RenameResult
    public func sayWhen(_ id: ChapterID, _ range: TimeRange) throws
    public func remove(_ id: ChapterID) throws -> ChapterReceipt?
    public func undoRemove(_ receipt: ChapterReceipt) throws
    @discardableResult public func add(_ memory: MemoryID, to chapter: ChapterID) throws -> Chapter?
    @discardableResult public func add(_ memory: MemoryID, toChapterNamed name: String) throws -> Chapter?
    public func takeOut(_ memory: MemoryID) throws
}
```

- `ChapterRepository`: `rename(_:to:)`, `remove(_:) -> ChapterReceipt?`, `restore(_:)`. Each is one `db.writer.write`.

- [ ] **Step 1: Write the failing tests**
  - `renameTrimsAndSaves`: "  Maple St " gives `.renamed` and title "Maple St".
  - `renameToNothingIsRefused`: "   " gives `.empty`; the title is unchanged.
  - `renameToAnotherChaptersNameIsRefused`: chapters "Maple Street" and "Swim team"; rename the second to "maple street." gives `.taken` (compare with `MatchKey.of`). Renaming a chapter to its own name with new capitals gives `.renamed`.
  - `sayWhenStoresTheRangeAsStated`: `sayWhen(id, .stated(between: 2008, and: 2012))`; `statedYears` is that range. A range whose origin is `.inferred` is stored with origin `.stated` (the sheet's range is the person's word).
  - `removeTakesTheChapterAndClearsItsTags`: two members and one story filed in it. After `remove`: the chapter is gone, both memories exist with `chapterID == nil`, the story's `chapterID == nil`, and the receipt lists both members and the story.
  - `removeOfAMissingChapterReturnsNothing`.
  - `undoPutsEverythingBack`: after `undoRemove(receipt)` the chapter has the same id, title, range and order, and the members and the story point at it.
  - `undoSkipsAMemberThatWasDeleted` and `undoSkipsAMemberTaggedElsewhere` (Review Focus 2): after `remove`, delete one member and assign the other to a second chapter; `undoRemove` restores the chapter and throws nothing; the second member keeps its new chapter.
  - `undoTwiceIsHarmless`: the second call changes nothing.
  - `addToANewNameMakesTheChapter`, `addToAnExistingNameReusesIt` ("maple street" finds "Maple Street"), `addWithAnEmptyNameCreatesNothing` (returns nil; chapter count unchanged; the memory's tag unchanged).
  - `addMovesTheTagAndPrunesTheChapterItLeft`: the memory was the only member of an untitled chapter; after `add` to another, the untitled chapter is gone.
  - `takeOutClearsTheTagAndPrunes`: the same prune; a named chapter with no members stays.
  - `deletingTheLastMemberPrunesAnUntitledChapter`: an untitled chapter with one member and no stated years; delete the memory with the action the Timeline's "Delete…" uses. The chapter is gone. If that action does not prune today, add the `deleteEmptyUntitled()` call to it.
  - `aMomentDatedOutsideTheStatedYearsKeepsItsTag`: stated 2008 to 2012, member stated 1990; after `add` and a `ResolverRunner.run()`, `chapterID` is still the chapter.
- [ ] **Step 2: Run** `swift test --filter ChapterActionsTests`. Expected: does not compile.
- [ ] **Step 3: Implement.** `restore` inserts the chapter row, then runs `update memory set chapter_id = ? where id in (…) and chapter_id is null`, and the same for `story`. `remove` reads the member and story ids before it deletes, in the same write. `add` and `takeOut` call `deleteEmptyUntitled()` after the write, as `CandidateActions.assign` does. Keep `CandidateActions.assign(memory:toChapter:)` as the one write path for a tag and call it from `ChapterActions`.
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `Chapter actions: rename, say when, remove with undo, add and take out`.

### Task 5: "Add to a chapter…" and "Take out" on a row

**Files:**
- Create: `ios/Lifeline/Screens/Chapters/AddToChapterSheet.swift`
- Modify: `Screens/Timeline/MemoryRowView.swift` (menu items and the `actions` type), `TimelineScreen.swift` (sheet state), `TimelineViewModel.swift` (`chapters`, `addToChapter`, `takeOutOfChapter`), `ios/Lifeline/Dependencies.swift` (a `chapterActions` member, at the end of the block)

**Interfaces:**
- Consumes: `ChapterActions.add`, `takeOut` (Task 4); `Chapter.name`.
- Produces: `MemoryRow.chapterID: ChapterID?`; `TimelineViewModel.namedChapters: [Chapter]`; identifiers `row.addChapter`, `row.takeOutOfChapter`, `chapter.pick` (one per listed chapter, label is the name), `chapter.newName`, `chapter.add`, `chapter.cancel`.

- [ ] **Step 1: Add the menu items.** "Add to a chapter…" (`row.addChapter`, system image `bookmark`) sits after "Add to a collection…". "Take out of “{name}”" (`row.takeOutOfChapter`) shows only when the row has a chapter with a name. Both show for moments only, on the spine, in stories and on the shelf.
- [ ] **Step 2: Build the sheet.** Title "Add to a chapter". A list of the named chapters, each a button; the row's current chapter has a checkmark and is disabled. Under the list, a text field "A new chapter, in your own words" (`chapter.newName`) and a button "Add" (`chapter.add`), disabled while the trimmed name is empty. A tap on a chapter or on Add calls the view model, then dismisses. With no chapters, the list does not show; the field and one line "A chapter is a name you gave to a stretch of your life." show.
- [ ] **Step 3: Wire the view model.** `addToChapter(_ memory: MemoryID, chapter: ChapterID)`, `addToChapter(_ memory: MemoryID, named: String)`, `takeOutOfChapter(_ memory: MemoryID)`; each uses the existing `attempt(_:_:)` and then `refresh()`.
- [ ] **Step 4: Build** the app for the simulator. Expected: build succeeds. Run `SpineUITests` and `TimelineUITests`. Expected: pass (the menu has new items; no existing assertion counts menu items — if one does, report it, do not change it).
- [ ] **Step 5: Commit** `A row's menu adds a moment to a chapter and takes it out`.

### Task 6: The life map's layout

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/LifeMap.swift`
- Test: `LifeMapTests.swift` (create)

**Interfaces:**
- Consumes: `Chapter.statedYears`, `Chapter.name`, `LifePeriod.containing(year:birthYear:)`.
- Produces:

```swift
public struct LifeMap: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let id: ChapterID
        public let title: String          // the name, or "No name yet"
        public let start: Double          // 0...1 along the axis
        public let end: Double            // 0...1; 1 when the chapter has no stated end
        public let yearsText: String      // TimeRange.displayText of the stated years
        public let momentCount: Int
    }
    public struct Band: Sendable, Equatable { public let name: String; public let start: Double; public let end: Double }
    public struct Unplaced: Sendable, Equatable, Identifiable { public let id: ChapterID; public let title: String; public let momentCount: Int }
    public let startYear: Int
    public let endYear: Int
    public let rows: [Row]
    public let periods: [Band]
    public let unplaced: [Unplaced]
    public let axisYears: [Int]           // every fifth year inside the axis, for the labels
    public var isEmpty: Bool { rows.isEmpty && unplaced.isEmpty }
    public init(chapters: [Chapter], momentCounts: [ChapterID: Int], birthYear: Int?, currentYear: Int)
    public func summary(of row: Row) -> String   // VoiceOver: "Maple Street, 1998–2001, 3 moments"
}
```

- [ ] **Step 1: Write the failing tests**
  - `rowsAreInOrderOfStartThenLongestFirst`: chapters 2000 to 2003, 1998 to 2001, 2000 to 2010. Row titles in order: the 1998 one, the 2000 to 2010 one, the 2000 to 2003 one.
  - `theAxisRunsFromTheBirthYearToNow`: birth 1990, current 2026: `startYear == 1990`, `endYear == 2026`; a chapter 2008 to 2012 has `start == 18.0/37.0` and `end == 23.0/37.0` (a year is one unit wide; the axis has `endYear - startYear + 1` units).
  - `withNoBirthYearTheAxisStartsAtTheEarliestChapter`.
  - `aChapterBeforeTheBirthYearMovesTheAxisStart` (Review Focus 5): birth 1990, chapter 1985 to 1988: `startYear == 1985`, and no `start` is below 0.
  - `aChapterWithNoStatedEndRunsToTheRightEdge`: a stated range with `latest == nil` gives `end == 1`.
  - `aChapterThatEndsAfterNowIsCutAtTheRightEdge`: `end == 1`.
  - `chaptersWithoutStatedYearsAreUnplaced`: one unplaced and one with a derived range are both in `unplaced`, in the chapters' stored order, and not in `rows`.
  - `aChapterWithNoNameReadsNoNameYet`: title "No name yet", in `rows` or `unplaced` by its years.
  - `periodsCoverTheAxisByAge`: birth 1990, current 2026: bands "Childhood" 1990 to 2002, "Teens" 2003 to 2009, "Twenties", "Thirties"; each band's `end` equals the next band's `start`; the last `end == 1`. With no birth year the bands are decades ("The 2000s").
  - `thirtyChaptersAllGetARow` (Review Focus 5).
  - `noChaptersIsEmpty`: `isEmpty == true`, `rows`, `unplaced` and `periods` hold nothing a view would draw as a frame (`periods` may be computed; the view hides them when `isEmpty`).
  - `theSummaryNamesTheYearsAndTheCount` (use the exact text `TimeRange.displayText` gives for the range): "Maple Street, 1998–2001, 3 moments"; "1 moment" for one; no count text for zero ("Maple Street, 1998–2001").
- [ ] **Step 2: Run** `swift test --filter LifeMapTests`. Expected: does not compile.
- [ ] **Step 3: Implement.** Build the period bands by walking the axis years and joining neighbours with the same `LifePeriod.containing(year:birthYear:).name`.
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `LifeMap: every chapter as a bar on one year axis`.

### Task 7: The chapter's sheet, the life map and the tag

**Files:**
- Create: `Screens/Chapters/ChapterSheet.swift`, `ChapterSheetViewModel.swift`, `LifeMapSheet.swift`, `LifeMapViewModel.swift`, `LifeMapRow.swift`
- Modify: `Screens/Timeline/ChapterTag.swift` (a `Button`), `MemoryRowView.swift` (pass the tap up), `TimelineScreen.swift` (the "Chapters" menu item, both sheets, the removal notice), `TimelineViewModel.swift`

**Interfaces:**
- Consumes: `ChapterActions` (Task 4), `LifeMap` (Task 6), `TellMeWhenSheet`, `NoticeSlot`, `ShellNotice.duration` (6 seconds).
- Produces: identifiers `timeline.tag` (unchanged, now a button), `timeline.chapters`, `lifemap.sheet`, `lifemap.row` (label from `LifeMap.summary(of:)`), `lifemap.unplaced`, `lifemap.sayWhen`, `lifemap.empty`, `lifemap.done`, `chapter.sheet`, `chapter.name`, `chapter.years`, `chapter.member`, `chapter.rename`, `chapter.renameField`, `chapter.renameSave`, `chapter.renameTaken`, `chapter.sayWhen`, `chapter.remove`, `chapter.confirmRemove`, `chapter.removed` (the notice), `chapter.undo`.

- [ ] **Step 1: The chapter's sheet.** It shows the name (or "No name yet"), then the stated years as `displayText`, or "No dates yet", then the said members as rows of title and date text in time order. With no members the list does not show. Buttons: "Rename" (an alert with a text field; Save disabled when empty; when the result is `.taken` the sheet shows "You already have a chapter with this name." and keeps the alert's text), "Say when it was" (`TellMeWhenSheet(title: name, birthDate:, heading: "From when to when?")`, result to `sayWhen`), "Remove chapter…" (destructive; a confirmation dialog titled "Remove “{name}”?" with the message from Global Constraints, a destructive button "Remove chapter" and "Cancel"). Under the buttons, in caption text: "Removing a chapter never removes a memory. Its moments stay on your timeline."
- [ ] **Step 2: Removal and undo.** On confirm, the sheet's view model calls `remove`, hands the receipt to its owner through `onRemoved: (ChapterReceipt) -> Void`, and the sheet dismisses. The Timeline view model holds `removedChapter: ChapterReceipt?`, clears it after `ShellNotice.duration`, and has `undoRemoveChapter()`. The Timeline shows `NoticeSlot(text: "Removed “{name}”.", identifier: "chapter.removed")` with a trailing "Undo" button, in the same place You shows its notice (`YouScreen.swift:69`). When the life map presented the chapter's sheet, the life map stays open and reloads; the notice shows on the Timeline under it and on the life map's bottom edge. A second removal inside 6 seconds replaces the first notice; the first can no longer be undone.
- [ ] **Step 3: The life map.** A sheet, title "Chapters", "Done" (`lifemap.done`). When `isEmpty`: only the one sentence (`lifemap.empty`). Otherwise: the first line from Global Constraints; a vertical scroll of rows over shaded period columns with the period names at the top and `axisYears` at the bottom, "now" at the right edge; each row is a bar from `start` to `end` with the name beside it (inside the bar when it fits, else to its right; a long name truncates on one line). Then "Not placed in time yet" with each unplaced chapter's name and a "Say when" button. A tap on a row or on an unplaced name opens the chapter's sheet. At accessibility sizes the bars keep their place and the name moves to its own line above the bar. Colour is never the only sign: the bar has the name; a chapter with no end has an open right edge (no end cap).
- [ ] **Step 4: The tag and the menu.** `ChapterTag` takes `onTap` and is a `Button` with the same look; its accessibility label is "Chapter: {name}". It stays outside the row's main button (S6a ruling R15). The Timeline's "…" menu gets "Chapters" (`timeline.chapters`).
- [ ] **Step 5: Build**, then run `SpineUITests`, `TimelineUITests`, `SameStoryUITests`. Expected: pass. `SpineUITests` counts `timeline.tag` elements; if its query is by element type and the tag is now a button, change the query's type only and record it in the ledger.
- [ ] **Step 6: Commit** `The chapter's sheet, the life map, and a tag you can tap`.

### Task 8: UI tests

**Files:**
- Create: `ios/LifelineUITests/ChaptersUITests.swift`
- Modify: `ios/Lifeline/UITestSeed.swift` (`writeSpine` only if a step below needs it; add at the end of the function), `ios/LifelineUITests/UITestHelpers.swift` (helpers at the end)

The seed `-uiTesting-seedSpine` (`launchWithSpine`) has "The tree house" (1999, inferred) tagged "Maple Street", "The science fair" (2001) in a chapter with no name, and "Learning to swim" (2000) with no chapter. The launch repair runs after the seed and keeps both chapters, because each has a member.

- [ ] **Step 1: Write the tests.** See each fail against the build before Task 5 where the plan says "fails before".
  - `testATagOpensItsChaptersSheet`: tap `timeline.tag` "Maple Street"; `chapter.sheet` shows `chapter.name` "Maple Street", `chapter.years` "No dates yet", and one `chapter.member` "The tree house". Fails before.
  - `testSayWhenPutsTheChapterOnTheLifeMap`: in the sheet, "Say when it was", choose "Between two years" 1998 and 2001, save. `chapter.years` reads the range. Close; open `timeline.more` → `timeline.chapters`; one `lifemap.row` has a label that starts "Maple Street, 1998". Before the save, "Maple Street" is under `lifemap.unplaced`.
  - `testADatedMomentInsideAChaptersYearsGetsNoTag` (Review Focus 4): after the step above, "Learning to swim" (2000, inside 1998 to 2001) has no `timeline.tag` in its row; the count of `timeline.tag` on the whole timeline is still 1.
  - `testRenameShowsOnTheTag`: rename to "Maple St"; the tag on the Timeline reads "Maple St". Renaming to an empty name is not possible (`chapter.renameSave` is disabled).
  - `testRemoveKeepsTheMomentAndUndoBringsTheTagBack`: remove "Maple Street"; "The tree house" is still on the spine with no tag; `chapter.removed` reads "Removed “Maple Street”."; tap `chapter.undo`; the tag is back.
  - `testTheNoticeLeavesAfterSixSeconds`: after a removal, `chapter.removed` does not exist after 8 seconds, and the tag is still gone.
  - `testAddToANewChapterTagsTheMoment`: on "Learning to swim", `row.more` → `row.addChapter`; type "Swim team"; `chapter.add`. The row has a tag "Swim team". `chapter.add` is disabled while the field is empty or only spaces.
  - `testAddToAnExistingChapterAndTakeOut`: add "Learning to swim" to "Maple Street" with `chapter.pick`; two tags "Maple Street" show. `row.takeOutOfChapter` on it; one tag shows.
  - `testAChapterWithNoNameShowsOnTheLifeMapOnly`: no element on the Timeline has the label "Untitled chapter" or "No name yet"; the life map has "No name yet" under `lifemap.unplaced`; opening it and renaming it to "Mr. Okafor's class" puts that tag on "The science fair".
  - `testWithNoChaptersTheLifeMapSaysWhatAChapterIs`: launch with the seed that has no chapter (check `UITestSeed.write`; if it makes a chapter, remove both spine chapters in the test first). `lifemap.empty` exists; no `lifemap.row`, no "Not placed in time yet".
  - `testAtTheLargestTextTheSheetsAreReachable`: with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`, the tag is hittable, the sheet's three buttons are hittable after a scroll, and "Done" on the life map is hittable.
- [ ] **Step 2: Run** `ChaptersUITests`, `SpineUITests`, `TimelineUITests`, `OrganizeUITests`, `RepairUITests`. Expected: pass.
- [ ] **Step 3: Commit** `UI tests for chapters: tag, sheet, life map, remove and undo`.

### Task 9: Docs, screenshots, the full run

**Files:**
- Modify: `docs/DECISIONS.md` (one entry at the top: the ten builder's defaults and every ruling made while building; say that the decision of 2026-10-26 on chapter ranges from members is superseded), `docs/OVERVIEW.md` (the data model's chapter paragraph and the Timeline paragraph), `docs/specs/2026-11-16-timeline.md` (Status line: S6a and S6c built), `README.md` (Status)
- Create: `docs/plans/2026-11-18-timeline-chapters-device-check.md`, `docs/screenshots/timeline-chapters/`

- [ ] **Step 1: Write the device checklist.** One numbered check per behaviour a simulator cannot prove on the owner's own archive. It must include: an existing chapter that had dates before this build now shows "No dates yet" and sits under "Not placed in time yet"; a tag opens the right chapter; remove and undo on a real chapter; VoiceOver reads a life map row as name, years and count; the life map with the owner's real number of chapters; the largest text size.
- [ ] **Step 2: Screenshots** on the simulator with the spine seed, before (`main`) and after: the Timeline with a tag, the add sheet, the chapter's sheet, the life map with one placed and one unplaced chapter, the removal notice, the life map at the largest text size.
- [ ] **Step 3: Run** `swift test`, then the whole UI suite once. Record the counts in the ledger.
- [ ] **Step 4: Commit** `Docs: chapters as names with stated years (S6c)`.

## After S6c

- S6b: the pinned card opens the life map; the "During" line reads `Chapter.statedYears`.
- A tap on a said member in the chapter's sheet opens the memory.
- `story.chapter_id` has no reader; a later migration can drop it.
- Carried from S6a: the place on a row and the tap on a person or place (spec "The spine", rule 5); a softer gap label next to a guessed date.
