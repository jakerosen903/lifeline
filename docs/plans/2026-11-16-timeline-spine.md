# S6a: The Timeline Spine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Timeline is one spine of moments. Each moment has a mark and its year beside the spine. The space between two moments follows the years between them. Age periods show as waypoints. The chapter sections, their year axes, "Outside any chapter" and "Untitled chapter" go away. A moment the person put in a chapter shows that chapter's name as a tag.

**Architecture:** Tasks 1 to 3 are pure code in the kit: `LifePeriod` (a year to a period name), `SpineLayout` (ordered dates to marks, gaps and waypoints) and a `TimelineSummary` without the chapter count. Task 4 changes `TimelineViewModel` to build one ordered spine in place of chapter rows. Task 5 builds the views and deletes `ChapterSection` and `YearAxis`. Task 6 moves the UI tests. Task 7 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, Swift Testing, XCUITest. No migration. No new dependency. No network call.

**Spec:** `docs/specs/2026-11-16-timeline.md`, sections "The spine", "Gaps", "Periods", "Tags" (rule 1 only), "What leaves the Timeline", "Edge cases" and "Principles". `docs/DECISIONS.md`, entry of 2026-11-16 "The Timeline is a spine". Mock-up: `docs/design/TL_SpineStrip.dc.html` (this PR builds the list below the pinned card; the card is S6b).

**Worktree and branch:** `../lifeline-timeline`, branch `sections-timeline`, based on `origin/main` with `origin/claude/bold-ramanujan-c0uver` merged in (it holds this plan and the spec; docs only). Work only there.

---

## Decisions made in this plan

The spec leaves these open. Each one is decided here so the owner can overrule it before work starts.

1. **This PR shows the tag, read only.** The chapter sections are the only place a chapter shows today. Removing them without the tag would hide every chapter until S6c. So a moment whose `chapterID` names a chapter with a title shows that title as a tag. The tag does nothing on a tap yet. The life map and the chapter's sheet are S6c.
2. **"New chapter from here" is removed, with no replacement in this PR.** It is the action that makes untitled chapters. "Add to a chapter…" comes in S6c. Until then a chapter starts only from a chapter hint on a kept card, which always has a title.
3. **Stored data does not change.** No chapter is deleted, renamed or re-dated here. A chapter with no title shows nowhere. `chapter.range` is still written from members; S6c changes that. Nothing reads it on the Timeline after this PR.
4. **The margin shows years only.** The margin is narrow. It shows a year or a year span ("1999", "2008–10") and, for a guess, the word "around" above it. When the full date text says more than that ("June 2012", "before Graduation (2004)", "probably 1999–2001"), the row shows the full text under the title, as today. **Changed by the owner on 2026-11-16:** for a confirmed relation ("before Graduation (2004)") the margin shows no years and no qualifier. The far edge of that band is the builder's slack, and it must not read as a fact. The dashed capsule stays, and the row shows the full text.
5. **The mark, from the range.** Solid dot: `readsAsSaid` is true and the shown years are one year. Dashed dot: one shown year and `readsAsSaid` is false. Dashed capsule: the shown years are more than one year, whoever said it. "Shown years" are the likely band when there is one, else the possible band.
6. **The gap table.** Years between two moments are counted from the end of the earlier one's shown years to the start of the later one's, never below 0. Gap units: 0 or 1 year, 0 units; 2 years, 1; 3 to 4 years, 2; 5 to 9 years, 3; 10 years or more, 4. From 3 years the spine in the gap is dashed and carries the label "{n} years". The view gives each unit 14 points. The table is in the kit so a test pins it.
7. **A period is found from the start of the shown years.** A moment before the birth year, or at an age of 100 or more, gets a decade name ("The 1980s") and no "by your age".
8. **A story is one stop on the spine.** A story of two or more moments sits at the start of its span. Its mark is a dashed capsule when its span is more than one year, else a solid dot. **Changed by the owner on 2026-11-16:** the dot is solid only when every dated member reads as said; otherwise it is a dashed dot with "around". A story's span is derived, so the rule of decision 5 cannot be applied to it directly: `SpineLayout.storyRange(members:)` gives the range to lay out. Its members open under it without marks, with their date text in the row, as today.
9. **Collections do not change.** A moment in a collection still shows only in its collection's section, under the spine, as today. The spec says every moment sits on the spine; this plan does not do that for collection members, because it would show one memory twice on one screen. This is flagged for the owner in "After S6a".
10. **Rows sit on the linen, with no card and no separator,** so the spine reads as one line. The waiting cards, the collections and the shelf keep their look.
11. **At the accessibility text sizes the margin closes.** The row shows the full date text above the title. The spine and the marks stay.
12. **VoiceOver hears the date once.** The margin and the mark are hidden from accessibility. The row's label stays "{title} · {date} · {people}", unchanged, and gains " · {chapter}" when there is a tag. A gap label and a period waypoint are read.

### Limits found while planning

- **Between S6a and S6c a chapter cannot be made by hand, renamed or removed.** Decision 2. The owner's three stale chapters stop showing, which is the reported problem, and stay in the database.
- **`SameStoryUITests` and `TimelineUITests` assert the year axis.** The axis goes. Task 6 moves each assertion to the period waypoint, which shows exactly when a dated moment shows.
- **Photos (S4) is in progress in another worktree.** Both branches add a launch argument in `Dependencies.swift` and a seed in `UITestSeed.swift`. Expect a small merge conflict there; keep both.
- **Two simulators.** UI tests time out when another build uses the same simulator. Use a second device for this worktree: `xcrun simctl create "Lifeline Timeline" "iPhone 17 Pro"` and pass its id to `-destination`.

---

## Global Constraints

- No migration. `MigrationsTests` does not change. No file under `Store/` changes.
- No stored chapter, story or memory is written by this PR's new code. The PR only reads.
- Keep these accessibility identifiers: `timeline.memory`, `timeline.story`, `timeline.summary`, `timeline.sessions`, `timeline.more`, `timeline.showHidden`, `timeline.tagFilter`, `timeline.waiting`, `timeline.collection`, `timeline.shelf`, `timeline.error`, `row.more`, `row.addDate`, `row.addCollection`, `row.moveToStory`, `row.takeOut`, `row.hide`, `row.exclude`, `row.delete`, `row.confirmDelete`, `story.more`, `story.rename`, `story.split`, `home.start`.
- Remove these: `timeline.axis`, `timeline.chapter`. New ones: `timeline.period`, `timeline.gap`, `timeline.tag`.
- Copy, exact:
  - Waypoint: "{name} · by your age", or "{name}" for a decade. Names: "Childhood", "Teens", "Twenties", "Thirties", "Forties", "Fifties", "Sixties", "Seventies", "Eighties", "Nineties", "The 1980s".
  - Gap: "{n} years".
  - Margin qualifier: "around".
- The app must never show "Untitled chapter", "Outside any chapter" or "On the timeline".
- A gap label states time only. No "quiet years", no "nothing yet", no invitation (PRINCIPLES 9).
- A period name states an age or a decade. Never a life event (PRINCIPLES 1).
- A mark must not tell sure from unsure by colour alone: solid against dashed, dot against capsule (PRINCIPLES 5).
- Text colours: `Theme.ink`, `Theme.secondaryText`, `Theme.oliveText`, `Theme.ochreText`. The spine and marks use `Theme.ochre` and `Theme.ink` as marks. The tag uses `Theme.oliveOnFill` on its 20% olive fill, as a `.bordered` button does. No new colour value.
- Every control is at least 44 by 44 points. Dynamic Type must not clip.
- Pure logic lives in `LifelineKit/Domain/` with Swift Testing tests. One responsibility for each file.
- Kit tests: `cd ios/LifelineKit && swift test`. UI tests: `xcodebuild test -project ios/Lifeline.xcodeproj -scheme Lifeline -destination 'id=<simulator id>' -only-testing:LifelineUITests/<Class>`. Run `xcodegen generate` in `ios/` after adding or deleting app or UI-test files.
- UI test scope (owner, 2026-11-15): a task runs only the UI test classes it names. The whole UI suite runs once, in Task 7.
- No test's assertion is weakened. A test that asserts behaviour this plan removes moves to the new behaviour with an assertion of equal strength. The plan names each one.
- Fixtures are invented; never a real person's words.

## Review Focus

1. **The spine is continuous.** No break between two rows, through a gap, or at a waypoint, at the default and the largest text size. Task 5, device check.
2. **Order and gaps are right at the edges.** One moment; two in one year; overlapping ranges; a range inside a range; a half-open range; a moment before the birth year. Task 2.
3. **Nothing vanished.** Every moment that showed in a chapter section or under "Outside any chapter" shows on the spine. Task 4 (`everyPlacedLooseMomentIsOnTheSpine`).
4. **No chapter text leaks.** An untitled chapter shows nowhere. Task 6.
5. **Labels unchanged for VoiceOver** except the added chapter name. Task 5.

---

### Task 1: Kit — a year's life period

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/LifePeriod.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/LifePeriodTests.swift`

**Interface:**

```swift
/// A stretch of life named by the person's age, or by its decade when the age is unknown.
public struct LifePeriod: Equatable, Sendable {
    public let name: String
    /// True when the name comes from the birth date: the waypoint then says "by your age".
    public let byAge: Bool
    public static func containing(year: Int, birthYear: Int?) -> LifePeriod
}
```

**Rules:** age is `year - birthYear`. 0 to 12 "Childhood"; 13 to 19 "Teens"; 20 to 29 "Twenties"; then by tens to "Nineties". No birth year, a negative age, or 100 and over: "The {decade}s", `byAge` false.

**Tests (see each fail first):**

```swift
@Test func agesMapToTheirPeriod()          // birth 1990: 1990 and 2002 Childhood; 2003 and 2009 Teens; 2010 Twenties; 2089 Nineties; all byAge
@Test func withNoBirthYearItIsTheDecade()  // 2004 -> "The 2000s", byAge false
@Test func beforeBirthAndPastAHundredAreDecades() // birth 1990: 1984 -> "The 1980s"; 2090 -> "The 2090s"; byAge false
```

- [ ] **Step 1:** Write the tests. Run `swift test --filter LifePeriodTests`. Expected: FAIL (no such type).
- [ ] **Step 2:** Write `LifePeriod`.
- [ ] **Step 3:** Run `swift test`. Expected: PASS.
- [ ] **Step 4: Commit** — `Kit: a year's life period, by age or by decade`

### Task 2: Kit — the spine's layout

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/SpineLayout.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/SpineLayoutTests.swift`

**Interface:**

```swift
/// What the spine shows for an ordered list of dated things. Pure: it stores nothing.
public enum SpineLayout {
    public enum Mark: Equatable, Sendable { case solidDot, dashedDot, dashedCapsule }

    public struct Gap: Equatable, Sendable {
        public let years: Int
        /// 0...4, from the table in the plan's decision 6. The view turns a unit into points.
        public let units: Int
        /// "3 years", from three years up; nil below.
        public let label: String?
        public var isDashed: Bool { label != nil }
    }

    public struct Stop: Equatable, Sendable {
        public let id: String
        public let mark: Mark
        /// "1999" or "2008–10".
        public let years: String
        /// "around" for a dashed dot; nil otherwise.
        public let qualifier: String?
        /// False when the stop above shows the same years: the year is written once.
        public let showsYears: Bool
        /// The full date text, when it says more than the margin does; nil otherwise.
        public let rowDateText: String?
        /// The space above this stop; nil for the first stop.
        public let gapAbove: Gap?
        /// The period that starts at this stop; nil when the stop above is in the same one.
        public let periodAbove: LifePeriod?
    }

    /// `items` must be in display order and every range must be dated (`isDated`).
    public static func stops(for items: [(id: String, range: TimeRange)], birthYear: Int?) -> [Stop]
    static func gap(years: Int) -> Gap
}
```

**Rules:** the shown years are the likely band when both its ends exist, else `earliest` and `latest`. `years` uses `TimeRange.yearSpan`. The mark follows decision 5. `rowDateText` is nil when `displayText` equals `years` or "around " + `years`; else it is `displayText`. The gap follows decision 6. An item whose range is not dated is skipped; the caller must not pass one (a one-line comment says the view model filters first).

**Tests (see each fail first):**

```swift
@Test func emptyInGivesEmptyOut()
@Test func oneMomentHasNoGapAndStartsItsPeriod()
@Test func aStatedYearIsASolidDotAndAnInferredOneIsDashed()   // .stated(year:) -> solidDot, qualifier nil; .year(_, origin: .inferred) -> dashedDot, "around"
@Test func aStatedAroundIsADashedDot()                        // .stated(around: 1999): readsAsSaid is false -> dashedDot, years "1999", qualifier "around", rowDateText nil
@Test func aRangeOfYearsIsACapsule()                          // .stated(between: 2008, and: 2010) -> dashedCapsule, years "2008–10", rowDateText nil
@Test func aFinerDateKeepsItsFullTextInTheRow()               // a month-granularity range -> years "2012", rowDateText "June 2012"
@Test func aRelationKeepsItsFullTextInTheRow()                // confirmed, evidence "before Graduation (2004)" -> rowDateText is that text
@Test func theGapTable()                                      // gap(years:) for 0,1,2,3,4,5,9,10,40 -> units 0,0,1,2,2,3,3,4,4; label nil below 3, "3 years", "40 years"
@Test func aGapIsMeasuredFromTheEndOfARange()                 // 2008–10 then 2011 -> 1 year
@Test func overlappingRangesHaveNoGap()                       // 2000–05 then 2003 -> 0 years, never negative
@Test func theSameYearIsWrittenOnce()                         // 2001, 2001 -> second showsYears false; a third in 2002 true
@Test func aPeriodShowsOnlyWhereItStarts()                    // birth 1990: 1999, 2001, 2003, 2006 -> periodAbove Childhood, nil, Teens, nil
@Test func aMomentBeforeBirthGetsADecade()
@Test func undatedItemsAreSkipped()                           // a half-open range in the input gives no stop and does not break the gaps around it
```

- [ ] **Step 1:** Write the tests. Run `swift test --filter SpineLayoutTests`. Expected: FAIL.
- [ ] **Step 2:** Write `SpineLayout`.
- [ ] **Step 3:** Run `swift test`. Expected: PASS.
- [ ] **Step 4: Commit** — `Kit: the spine's marks, gaps and waypoints as a pure layout`

### Task 3: Kit — the summary no longer counts chapters

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Domain/TimelineSummary.swift` (`text` loses its `chapters` parameter)
- Test: `ios/LifelineKit/Tests/LifelineKitTests/TimelineSummaryTests.swift`

The four existing `text(...)` expectations lose `chapters:`. The first one's expected string loses " · 1 chapter". No other expectation changes. This is the one assertion in the kit that moves.

- [ ] **Step 1:** Change the test. Run `swift test --filter TimelineSummaryTests`. Expected: FAIL to compile.
- [ ] **Step 2:** Change `text`. The app does not compile until Task 4; that is expected.
- [ ] **Step 3:** Run `swift test`. Expected: PASS.
- [ ] **Step 4: Commit** — `Kit: the Timeline summary does not count chapters`

### Task 4: App — the view model builds one spine

**Files:**
- Modify: `ios/Lifeline/Screens/Timeline/TimelineViewModel.swift`

**What changes:**

- `MemoryRow` gains `var chapterTitle: String? = nil`: the title of the memory's chapter, trimmed, nil when the chapter has no title or the title is empty. `row(for:birth:)` takes the chapters as a dictionary read once in `refresh()`; it must not read a chapter for each row.
- A new type and property:

```swift
/// One stop on the spine: a moment or a story, with what `SpineLayout` says about it.
struct SpineRow: Identifiable, Equatable {
    enum Content: Equatable { case memory(MemoryRow), story(StoryRow) }
    let content: Content
    let stop: SpineLayout.Stop
    var id: String { stop.id }
}
private(set) var spine: [SpineRow] = []
```

- `refresh()` builds `spine` from the placed loose moments and the placed stories, whatever their chapter, merged and sorted by time. A story sorts by its span with the rule `byTime` uses. An entry whose range is not `isDated` is left out of `SpineLayout` and goes to the shelf list instead, so nothing disappears. Add a comment that says why.
- Remove `ChapterRow`, `chapters`, `unchaptered`, `unchapteredStories`, `axis` and `newChapter(for:title:)`.
- `memoryCount` counts `spine` (a story counts its members), the collections, the shelf and its stories, and `aboutCount` as today.
- `summary` calls the new `TimelineSummary.text`.
- `siblings(of:)` still reads `memories(inChapter:)`. Do not change it: the questions are not part of this PR.

**Test:** the view model has no unit test target. Add the check as a kit-level pure function only if it falls out naturally; otherwise it is covered by Task 6's `everyPlacedMomentIsOnTheSpine`. State in the ledger which one you did.

- [ ] **Step 1:** Make the changes. The app builds once Task 5's views exist; to keep this commit green, do Task 4 and Task 5 on one build cycle and commit them apart only if each compiles. If they cannot compile apart, commit them together and say so in the ledger.
- [ ] **Step 2: Commit** — `Timeline: the view model builds one spine in place of chapter rows`

### Task 5: App — the spine on screen

**Files:**
- Create: `ios/Lifeline/Screens/Timeline/SpineRowView.swift` (the margin, the mark, the gap and the row's content)
- Create: `ios/Lifeline/Screens/Timeline/SpineMark.swift` (the three marks as one small view)
- Create: `ios/Lifeline/Screens/Timeline/ChapterTag.swift`
- Modify: `ios/Lifeline/Screens/Timeline/TimelineScreen.swift`, `MemoryBand.swift`, `StorySection.swift`, `ShelfSection.swift`
- Delete: `ios/Lifeline/Screens/Timeline/ChapterSection.swift`, `ios/Lifeline/Screens/Timeline/YearAxis.swift`
- Then: `cd ios && xcodegen generate`

**What to build:**

- `TimelineScreen.chapterSections` becomes `spineSection`: one `Section` with no header and one list row for each `SpineRow`. Each row has `.listRowSeparator(.hidden)`, `.listRowBackground(Color.clear)` and zero vertical insets, so the spine segments of two rows touch.
- `SpineRowView` draws, top to bottom: the gap (height `units × 14`, the spine through it, dashed when `isDashed`, the label beside it under `timeline.gap`); the waypoint when `periodAbove` is set (under `timeline.period`, a header for VoiceOver); then the row: the margin with `qualifier` and `years` (only when `showsYears`), the mark on the spine, and the content.
- The spine is one 2-point line in `Theme.ochre` that runs the full height of every spine row. The first row's line starts at its mark; the last row's ends at its mark.
- The content is today's `MemoryRowView` or `StoryRowView`, with these changes:
  - `MemoryBand` loses its `axis` parameter and the bar drawing. Rename it `MemoryText`, in a file of that name: it now shows text only.
  - Under the title it shows `rowDateText` when set, then the people line, then the tag.
  - `MemoryRowView` and `StoryRowView` lose their `axis` parameter. The shelf and the collections pass nothing.
  - On the spine the row's date colour rule stays: ochre text for a guess.
- `ChapterTag` shows `chapterTitle` on one line, truncated, under `timeline.tag`. It is not a button in this PR.
- The row's accessibility label is "{title} · {subtitle}" as today, plus " · {chapterTitle}" when set. The margin and the mark are `accessibilityHidden`.
- `MemoryRowActions` loses `newChapter`. The menu loses "New chapter from here".
- At `dynamicTypeSize.isAccessibilitySize` the margin is not drawn, the content starts just right of the spine, and the full date text shows above the title for every row.

**Edge cases to handle, each with a line in the ledger:** no dated moment (no spine section at all); one moment (a mark, no line above or below); a story open with its members (the spine continues beside them, no marks); a very long title (wraps; the mark stays at the first line); a very long chapter name (the tag truncates).

- [ ] **Step 1:** Build the views. Run the app in scripted mode with `-uiTesting -uiTesting-seedPeople` and look at it at the default and the largest text size.
- [ ] **Step 2:** Run `swift test`. Expected: PASS. Run `-only-testing:LifelineUITests/ShellUITests`. Expected: PASS (it scrolls the Timeline to its last row).
- [ ] **Step 3: Commit** — `Timeline: moments on one spine, with real gaps and age waypoints`

### Task 6: UI tests — a seed with gaps, and the moved assertions

**Files:**
- Modify: `ios/Lifeline/UITestSeed.swift` (add `writeSpine`), `ios/Lifeline/Dependencies.swift` (`-uiTesting-seedSpine`)
- Modify: `ios/LifelineUITests/UITestHelpers.swift` (add `launchWithSpine(_:)`)
- Create: `ios/LifelineUITests/SpineUITests.swift`
- Modify: `ios/LifelineUITests/TimelineUITests.swift` (lines 50 and 69), `ios/LifelineUITests/SameStoryUITests.swift` (line 109)

**The seed (invented; owner "Jordan", born 1990):** "The tree house" (inferred 1999, in the chapter "Maple Street"), "Learning to swim" (stated 2000), "The science fair" (stated 2001), "Maya's graduation" (stated 2003), "The first gig" (stated 2006), "The first apartment" (stated between 2008 and 2010). One chapter with no title that holds "The science fair". One undated moment, "The blue kite".

**New tests:**

```swift
func testEveryPlacedMomentIsOnTheSpine()        // the six dated titles each match one timeline.memory button; "The blue kite" is on the shelf
func testWaypointsNameThePeriodsOnce()          // timeline.period: one "Childhood · by your age", one "Teens · by your age", in that order
func testAThreeYearGapSaysSo()                  // exactly one timeline.gap, labelled "3 years"; none says "2 years"
func testAChapterTheOwnerNamedShowsAsATag()     // "The tree house" row's label contains "Maple Street"; one timeline.tag
func testNoChapterHeadingsAndNoUntitledChapter()// no static text "Untitled chapter", "Outside any chapter" or "On the timeline"; no element timeline.chapter
func testTheRowMenuHasNoNewChapter()            // open row.more on a row: no button "New chapter from here"
func testAtTheLargestTextTheDateSitsAboveTheTitle() // launch with UICTContentSizeCategoryAccessibilityXXXL: "The first apartment" row is hittable after reveal and its label holds "2008–10"
```

**Moved assertions (equal strength):**

- `TimelineUITests` line 50, "no year axis when nothing is placed": becomes `XCTAssertFalse(app.any("timeline.period").exists, "no waypoint when nothing is placed")`.
- `TimelineUITests` line 69, "a placed memory brings the year axis": becomes `XCTAssertTrue(app.any("timeline.period").waitForExistence(timeout: 3), "a placed memory brings its period")`. If that test's data has no birth date, the waypoint is a decade; the assertion is the same.
- `SameStoryUITests` line 109: the same replacement as line 69.

Read each of the three tests in full before you change it. If the surrounding test depends on the axis in another way, stop and write the ruling in the ledger before you go on.

- [ ] **Step 1:** Write the seed, the helper and `SpineUITests`. Run `-only-testing:LifelineUITests/SpineUITests`. Each new test must be seen failing for the right reason on a build without Task 5's change where that is practical (at least `testNoChapterHeadingsAndNoUntitledChapter` and `testAThreeYearGapSaysSo`); say in the ledger which you saw fail.
- [ ] **Step 2:** Move the three assertions. Run `-only-testing:LifelineUITests/TimelineUITests -only-testing:LifelineUITests/SameStoryUITests -only-testing:LifelineUITests/SpineUITests -only-testing:LifelineUITests/OrganizeUITests -only-testing:LifelineUITests/SteadyUITests`. Expected: PASS.
- [ ] **Step 3: Commit** — `UI tests: the spine seed, the spine's checks, and the axis checks moved to the waypoint`

### Task 7: Docs, screenshots and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` (the Timeline's description), `docs/DECISIONS.md` (one entry for the rulings made while building, if any), `README.md` (Status: the spine has shipped, when it merges)
- Create: `docs/plans/2026-11-16-timeline-spine-device-check.md`, `docs/screenshots/timeline-spine/` (before and after)

**Screenshots (simulator, `-uiTesting-seedSpine`):** before is `origin/main` with the seed cherry-picked onto a scratch branch; after is this branch. Take the Timeline at the top, the Timeline scrolled to the gap, the Timeline at the largest text size, and a row's menu.

**Device checklist (the owner ticks each on the iPhone, with the real archive):**

1. Back up the archive, then install. Every earlier memory that had a date is on the spine.
2. The three old chapters with no moments do not show. No "Untitled chapter". No "Outside any chapter".
3. The spine is one unbroken line from the first moment to the last, through every gap and waypoint.
4. A long quiet stretch is visibly longer than a short one, and its label gives the right number of years.
5. A date you are unsure of looks different from a date you stated, without relying on colour.
6. The waypoints match your age at the time.
7. At the largest text size nothing clips, and each date is readable.
8. VoiceOver reads a row as title, date, people, and the chapter when there is one. It reads each waypoint and each gap label.
9. Dark appearance: the spine and the marks are visible (there is no dark palette yet; report what you see).
10. Open a story on the spine. Its moments show under it, and the spine continues beside them.

- [ ] **Step 1:** Write the docs and the checklist. Take the screenshots.
- [ ] **Step 2:** Run `swift test` and the whole UI suite once. Record the counts and any failure with its cause in the ledger.
- [ ] **Step 3: Commit** — `Docs: the spine in the overview, its screenshots and its device checklist`

---

## After S6a

- **Collections (owner's call).** Should a dated moment that is in a collection also sit on the spine? Decision 9 keeps it off. If yes, the collection section must not repeat it, or must show it as a link.
- **Shelf count.** The shelf header counts a half-open moment ("before 2004") as "undated".
- **Collection and story.** A story member that is also in a collection shows in both places and is counted twice in the summary. This was so before this PR.
- **UI-test seed.** A seed with a story, a relation and a range of years would let the open-story and capsule cases run in CI.
- **People and places on a row.** The spec's "The spine" rule 5 says a row shows the people and the place, and a tap on a person or a place opens its page. S6a shows the people as plain text and shows no place. Neither is a button.
- **The waypoint above a relation.** Ruling R18 removes the gap label next to a confirmed relation. The waypoint above a relation still comes from the start of its band, and that start can be the builder's slack. The period it names can be wrong by the slack.
- **S6b:** the pinned card. `spine` already holds what the frame needs: the years of the rows on screen.
- **S6c:** the tag becomes a button; the life map; the chapter's sheet; "Add to a chapter…"; `chapter.range` holds stated years only; empty untitled chapters are deleted.
