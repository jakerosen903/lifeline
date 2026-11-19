# Timeline pinned card (S6b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A card stays under the Timeline's title. It shows the whole life as a strip with one tick for each dated moment, a frame over the years on screen, and one "During" line that names the chapters whose stated years cover those years.

**Architecture:** One pure kit type, `TimelineCard`, computes the strip, the frame, the "During" names and the VoiceOver sentence from the dated ranges, the chapters and the years of the spine rows on screen. `SpineLayout.Stop` gains its numeric years so the app does not repeat that rule. The app tracks which spine rows are on screen, draws the card with the strip axis it already has for entity pages, and pins it with a top safe-area inset. A tap opens the life map from S6c.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), Swift Testing in `ios/LifelineKit`, XCUITest in `ios/LifelineUITests`, xcodegen.

**Spec:** `docs/specs/2026-11-16-timeline.md`, sections "The screen, top to bottom", "The pinned card", "Edge cases" and "Principles". Mock-up: `docs/design/TL_SpineStrip.dc.html`. This plan builds on S6a (`docs/plans/2026-11-16-timeline-spine.md`) and S6c (`docs/plans/2026-11-18-timeline-chapters.md`).

## Global Constraints

- **No migration and no change under `Store/`.** This PR's new code only reads.
- The card stays under the title while the list scrolls.
- The strip runs from the birth year to now. With no birth date it starts at the earliest dated moment. A moment dated before the birth year moves the start to that moment.
- Each dated moment is one tick. A moment with a range is a tick at the start of its range. A guessed date has a hollow tick (shape, not colour alone).
- The frame covers the years of the spine rows on screen. It moves as the list scrolls. With Reduce Motion on, it moves without animation.
- The "During" line names the chapters whose stated years overlap the frame's years. The longest chapter comes first. Names that do not fit become "+N". With no such chapter the card shows the strip alone: no "During" word, no empty line.
- A chapter has stated years only as `Chapter.statedYears` says (S6c). A chapter with no name is never in the "During" line. A date overlap puts a chapter in the "During" line only; it never tags a moment.
- A tap on the card opens the life map. The strip is not a scrubber: a drag on it must not scroll the list.
- VoiceOver reads the card as one element. Exact form: "Your life from 1998 to now. On screen: 1998 to 2003. During Maple Street, Summers at the lake and 2 more."
- With no dated moment the screen shows no card.
- At the largest text sizes the "During" line wraps to two lines before it truncates.
- No count of what is missing shows. The card asks for nothing (PRINCIPLES 9). The card shows a chapter's years only when the person stated them (PRINCIPLES 5).
- Docs under `docs/` use ASD-STE100 style. Fixtures are invented. Commit after each task, imperative one-line message. No AI attribution in commits or PR text.
- UI tests: per task, run only the classes the task names. Run the whole UI suite once, in Task 6. Use the simulator id given at execution time in every `xcodebuild -destination`.

## Builder's defaults the owner can overrule

1. **The "Chapters" item stays in the Timeline's "…" menu.** With no dated moment there is no card, and the life map must still be reachable.
2. **The frame keeps its last years when no spine row is on screen** (the waiting cards at the top, or the shelf at the end). Before any spine row was on screen, the card shows no frame.
3. **A row counts as on screen when half of it is visible.** A row under the pinned card counts while it is in the scroll view's visible area.
4. **The visible "During" text follows the mock-up:** the word "During", then names joined by " · ", then "+N". VoiceOver uses the spec's sentence, with at most two names and "and N more".
5. **`LifeStrip` gains a choice of where a mark sits.** The entity page keeps the middle of the band. The Timeline card uses the start, as the spec says. The entity page does not change.
6. **"Longest first" ties** go to the earlier start, then to the name in alphabetical order. A chapter with no stated end counts as running to now.
7. **The card is in the Timeline tab only.**
8. **One year on screen reads "On screen: 1999."** Two or more read "On screen: 1998 to 2003."

## Review Focus

1. **The frame while a story is open or a row is deleted.** The set of rows on screen changes without a scroll. The frame must follow, and a row that is gone must not hold the frame open. Test in Task 2 (kit) and Task 5 (UI).
2. **Thirty chapters over the same years.** The "During" line shows what fits and "+N"; the card's height must not grow past two lines of names. Test in Task 2 (order and counts) and device check.
3. **A chapter whose stated years hold no moment.** It can show in the "During" line; no row gets a tag. Test in Task 2 and Task 5.
4. **One dated moment; a moment before the birth year; no birth date.** One tick, no division by zero, the axis starts at the right year. Tests in Task 1 and Task 2.
5. **The card under VoiceOver and at the largest text.** One element, the exact sentence, hittable, and the list is still reachable under it. Test in Task 5 and device check.

## File structure

| File | Responsibility |
| --- | --- |
| `ios/LifelineKit/Sources/LifelineKit/Domain/SpineLayout.swift` (modify) | `Stop.yearSpan` |
| `ios/LifelineKit/Sources/LifelineKit/Domain/LifeStrip.swift` (modify) | Where a mark sits |
| `ios/LifelineKit/Sources/LifelineKit/Domain/TimelineCard.swift` (create) | Frame, "During" names, sentences |
| `ios/Lifeline/Screens/Entities/LifeStripAxis.swift` (create, from `LifeStripView`) | The axis and its marks, with an optional frame |
| `ios/Lifeline/Screens/Timeline/TimelineCardView.swift` (create) | The card |
| `ios/Lifeline/Screens/Timeline/DuringLine.swift` (create) | The names that fit and "+N" |
| `ios/Lifeline/Screens/Timeline/TimelineViewModel.swift`, `TimelineScreen.swift`, `SpineRowView.swift` (modify) | Rows on screen, the card's inputs, the pin, the tap |
| `ios/LifelineUITests/TimelineCardUITests.swift` (create) | UI tests |

---

### Task 1: Numeric years on a stop, and a mark at the start

**Files:**
- Modify: `Domain/SpineLayout.swift`, `Domain/LifeStrip.swift`
- Test: `SpineLayoutTests.swift`, `LifeStripTests.swift`

**Interfaces:**
- Produces: `SpineLayout.Stop.yearSpan: ClosedRange<Int>?` (the first and last year the margin shows; nil for a confirmed relation, whose margin shows no years). `LifeStrip.MarkPlacement { case middle, start }` and `LifeStrip.init(moments:stated:birthYear:currentYear:marks: MarkPlacement = .middle)`.

- [ ] **Step 1: Write the failing tests**
  - `aStopCarriesItsYearsAsNumbers`: stated 2001 gives `2001...2001`; stated between 2008 and 2010 gives `2008...2010`; an age guess that reads "around 1999–2000" gives `1999...2000`.
  - `aConfirmedRelationHasNoYearSpan`: the stop the spine tests use for a confirmed relation has `yearSpan == nil`.
  - `yearSpanAgreesWithTheMarginText`: for each stop in the existing spine fixture, `years` (the string) starts with `String(yearSpan.lowerBound)` whenever `yearSpan` is not nil.
  - `aMarkCanSitAtTheStartOfItsRange`: moments stated between 2008 and 2010, birth 1990, current 2026, `marks: .start`: the one mark's position is `(2008 - 1990) / 37.0`. With `.middle` it is the existing value, `((2008 + 2010 + 1) / 2.0 - 1990) / 37.0`.
  - `theEntityPagesStripDoesNotChange`: the default argument is `.middle`; every existing `LifeStripTests` test passes unchanged.
  - `oneMomentIsOneMark`: one dated moment, `marks: .start`: `marks.count == 1`, position in `0...1`.
- [ ] **Step 2: Run** `swift test --filter SpineLayoutTests` and `--filter LifeStripTests`. Expected: do not compile.
- [ ] **Step 3: Implement.** `yearSpan` uses the same years `SpineLayout` already computes for `years`; do not compute them a second way.
- [ ] **Step 4: Run** `swift test`. Expected: pass (`ExtractionQueueTests.drainGivesUpAtItsDeadline` is a known flake).
- [ ] **Step 5: Commit** `A spine stop carries its years as numbers; a life strip mark can sit at the start`.

### Task 2: The card's layout

**Files:**
- Create: `Domain/TimelineCard.swift`
- Test: `TimelineCardTests.swift` (create)

**Interfaces:**
- Consumes: `LifeStrip(…, marks: .start)`, `Chapter.statedYears`, `Chapter.name`.
- Produces:

```swift
public struct TimelineCard: Sendable, Equatable {
    public struct During: Sendable, Equatable, Identifiable { public let id: ChapterID; public let name: String }
    public let strip: LifeStrip                    // marks at the start of each range
    public let frame: ClosedRange<Double>?         // 0...1 along the strip; nil when no years are on screen
    public let frameYears: ClosedRange<Int>?
    public let during: [During]                    // longest first; empty when no chapter overlaps
    public var isEmpty: Bool                       // no dated moment: the screen shows no card
    public init(moments: [TimeRange], chapters: [Chapter], onScreen: [ClosedRange<Int>], birthYear: Int?, currentYear: Int)
    public func duringText(showing count: Int) -> String?   // "Maple Street · Summers at the lake", nil when count is 0 or during is empty
    public func overflow(showing count: Int) -> String?     // "+2", nil when every name shows
    public var spokenText: String
}
```

- [ ] **Step 1: Write the failing tests**
  - `theFrameCoversTheYearsOnScreen`: birth 1990, current 2026, `onScreen: [1999...1999, 2000...2000, 2003...2003]`: `frameYears == 1999...2003`, `frame == (9.0/37.0)...(14.0/37.0)` (a year is one unit; the frame ends after its last year).
  - `nothingOnScreenIsNoFrame`: `onScreen: []` gives `frame == nil` and `frameYears == nil`.
  - `aFrameIsClampedToTheStrip`: `onScreen: [1980...1985]` with birth 1990 and a moment in 1999: the bounds are inside `0...1`.
  - `aRowThatLeftDoesNotHoldTheFrame` (Review Focus 1): two cards built from `[1999...1999, 2010...2010]` and then `[1999...1999]`: the second has `frameYears == 1999...1999`.
  - `duringNamesTheChaptersThatOverlapTheFrame`: chapters "Maple Street" 1998 to 2001, "The band" 2005 to 2007, frame 1999 to 2003: `during.map(\.name) == ["Maple Street"]`.
  - `aChapterThatTouchesTheFrameByOneYearCounts`: frame 2001 to 2003, chapter 1998 to 2001: in.
  - `theLongestChapterComesFirst`: 1998 to 2001 and 1995 to 2010 over frame 1999 to 2000: the 1995 one first. Ties (Builder's default 6): earlier start, then name.
  - `aChapterWithNoEndRunsToNow`: a stated range with no `latest` from 2015 overlaps frame 2024 to 2025, and its length counts to the current year.
  - `aChapterWithoutStatedYearsIsNeverDuring`: unplaced, derived and inferred ranges are out.
  - `aChapterWithNoNameIsNeverDuring`.
  - `aChapterWhoseYearsHoldNoMomentCanBeDuring` (Review Focus 3): no moment in 2005 to 2007; frame 2003 to 2006; "The band" is in `during`.
  - `noFrameIsNoDuring`: `onScreen: []` gives `during == []`.
  - `thirtyChaptersKeepTheirOrder` (Review Focus 2): thirty chapters over the same years: `during.count == 30`, `duringText(showing: 2)` has two names joined by " · ", `overflow(showing: 2) == "+28"`, `overflow(showing: 30) == nil`.
  - `duringTextForNoneIsNil`: `duringText(showing: 0) == nil`; with `during` empty, every call returns nil.
  - `withNoDatedMomentTheCardIsEmpty`: `isEmpty == true`. With one dated moment: `isEmpty == false`, `strip.marks.count == 1` (Review Focus 4).
  - `withNoBirthDateTheStripStartsAtTheFirstMoment`; `aMomentBeforeTheBirthYearMovesTheStart`.
  - `theSpokenTextIsTheSpecsSentence`: strip from 1998, frame 1998 to 2003, four overlapping chapters: "Your life from 1998 to now. On screen: 1998 to 2003. During Maple Street, Summers at the lake and 2 more."
  - Spoken text cases: one chapter "During Maple Street."; two "During Maple Street and Summers at the lake."; three "During Maple Street, Summers at the lake and 1 more."; none: no "During" sentence; no frame: only "Your life from 1998 to now."; one year on screen: "On screen: 1999."
- [ ] **Step 2: Run** `swift test --filter TimelineCardTests`. Expected: does not compile.
- [ ] **Step 3: Implement.** The strip is `LifeStrip(moments:stated:.unplaced,birthYear:currentYear:marks:.start)`; positions for the frame use the strip's `startYear` and `endYear` with the same arithmetic as the strip (one unit for each year, `endYear + 1 - startYear` units).
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `TimelineCard: the frame, the During names and the spoken sentence`.

### Task 3: The strip's axis as its own view

**Files:**
- Create: `ios/Lifeline/Screens/Entities/LifeStripAxis.swift`
- Modify: `ios/Lifeline/Screens/Entities/LifeStripView.swift`

**Interfaces:**
- Produces: `LifeStripAxis(strip: LifeStrip, frame: ClosedRange<Double>? = nil)`, a view that draws the line, the stated span, the marks and, when `frame` is not nil, the frame: a rounded outline in the olive colour of the mock-up (2 points) over the strip's full height, with a smallest width of 10 points, kept inside the strip at both ends.

- [ ] **Step 1: Move** the private `axis` of `LifeStripView` into `LifeStripAxis`, unchanged in look. `LifeStripView` uses `LifeStripAxis(strip: strip)`.
- [ ] **Step 2: Add** the frame. The frame's position animates with `.animation(reduceMotion ? nil : .snappy, value: frame)`; read `@Environment(\.accessibilityReduceMotion)`.
- [ ] **Step 3: Build**, then run `EntityPageUITests` and `EntitiesUITests`. Expected: pass, no assertion changed (the entity page must look and read the same).
- [ ] **Step 4: Commit** `The life strip's axis is a view of its own, with an optional frame`.

### Task 4: The card on the Timeline

**Files:**
- Create: `ios/Lifeline/Screens/Timeline/TimelineCardView.swift`, `ios/Lifeline/Screens/Timeline/DuringLine.swift`
- Modify: `TimelineViewModel.swift`, `TimelineScreen.swift`, `SpineRowView.swift`

**Interfaces:**
- Consumes: `TimelineCard` (Task 2), `SpineLayout.Stop.yearSpan` (Task 1), `LifeStripAxis` (Task 3), `TimelineViewModel.lifeMap()` and the `lifeMap` sheet state (S6c).
- Produces: `TimelineViewModel.card: TimelineCard`, `TimelineViewModel.setOnScreen(_ id: String, _ visible: Bool)`; identifiers `timeline.card` (the one accessibility element; label is `spokenText`; trait button; hint "Opens your chapters"), `timeline.cardStrip`, `timeline.during`.

- [ ] **Step 1: The view model.** It holds `onScreenIDs: Set<String>` (not persisted). `card` is built from: the ranges of every dated moment on the spine (a story gives one range for each dated member), `store.chapters.chapters()` as read in `refresh()`, the `yearSpan` of each spine row whose id is in `onScreenIDs`, the birth year and the current year. `refresh()` removes ids that are no longer spine rows (Review Focus 1). When `onScreenIDs` becomes empty, the card keeps the last non-empty set's years (Builder's default 2).
- [ ] **Step 2: Rows on screen.** `SpineRowView` reports with `.onScrollVisibilityChange(threshold: 0.5) { viewModel.setOnScreen(row.id, $0) }`. If that modifier does not fire for a row in this `List`, use `.onAppear` and `.onDisappear` on the row and record the change in the ledger.
- [ ] **Step 3: The card.** A rounded card in the list's card colour, laid out as `docs/design/TL_SpineStrip.dc.html` draws it (the mock-up's ticks are thin upright lines; a guessed date keeps the hollow tick the Global Constraints require, which the mock-up does not show): `LifeStripAxis(strip: card.strip, frame: card.frame)` at the height `LifeStripView` uses, then the start year and "now" in footnote text, then `DuringLine`. The whole card is one `Button` that sets `lifeMap = viewModel.lifeMap()`. `accessibilityElement(children: .ignore)`, label `card.spokenText`. No drag gesture on the strip.
- [ ] **Step 4: The "During" line.** Shows nothing when `card.during` is empty. Else, as the mock-up draws it: "During" in secondary text, then the names in olive semibold text, then "+N" in secondary text at the trailing edge. Use `ViewThatFits(in: .horizontal)` over candidates from all the names down to one name; each candidate is `duringText(showing: n)` on one line with `overflow(showing: n)` beside it. The last candidate (one name) truncates with a tail ellipsis. At accessibility sizes each candidate may use two lines (`lineLimit(2)`) before the next candidate is tried.
- [ ] **Step 5: The pin.** `timelineRows` gets `.safeAreaInset(edge: .top, spacing: 0)` with the card, inside the same horizontal padding as the list's rows and with the screen's background behind it, so rows do not show through. The inset holds nothing when `card.isEmpty`. The summary line stays the list's first row and scrolls away under the card.
- [ ] **Step 6: Build**, then run `SpineUITests`, `TimelineUITests`, `ChaptersUITests`, `SameStoryUITests`. Expected: pass. These tests scroll and tap rows; the card covers the top of the list. If a tap now lands on the card, report the test and the line; do not change an assertion.
- [ ] **Step 7: Commit** `The Timeline pins a card: life strip, frame and During line`.

### Task 5: UI tests

**Files:**
- Create: `ios/LifelineUITests/TimelineCardUITests.swift`
- Modify: `ios/LifelineUITests/UITestHelpers.swift` (helpers at the end, only if needed)

The seed `-uiTesting-seedSpine` has Jordan, born 1990, moments in 1999 (inferred), 2000, 2001, 2003, 2006 and 2008 to 2010, one undated moment, the chapter "Maple Street" (no stated years) on "The tree house", and a chapter with no name on "The science fair".

- [ ] **Step 1: Write the tests**
  - `testTheCardReadsTheLifeAndTheYearsOnScreen`: at launch `timeline.card` exists, is hittable, and its label starts "Your life from 1990 to now. On screen: 1999 to ". The label holds no "During".
  - `testTheCardStaysWhileTheListScrolls`: scroll to "The first apartment"; `timeline.card` is still hittable, and its frame's `minY` is the same as at launch (within 2 points).
  - `testTheFrameFollowsTheList` (Review Focus 1): after the scroll to the end of the spine, the label's "On screen" years end at 2010 and no longer start at 1999.
  - `testDuringNamesAChapterOnlyWhileItsYearsAreOnScreen`: say when for "Maple Street" between 1998 and 2001 (the steps `ChaptersUITests` uses). At the top the label ends "During Maple Street." After the scroll to the end the label holds no "During".
  - `testAChapterInTheDuringLineTagsNoOtherMoment` (Review Focus 3): after the say-when, the tags on the whole timeline are still exactly `["The tree house": "Maple Street"]` (reuse the helper in `ChaptersUITests`; move it to `UITestHelpers.swift`).
  - `testAChapterWithNoNameIsNotInTheDuringLine`: say when for the chapter with no name (from the life map) between 1999 and 2003; the card's label holds no "During" and no "No name yet".
  - `testATapOnTheCardOpensTheLifeMap`: tap `timeline.card`; `lifemap.sheet` exists. "Done" returns to the Timeline with the card in place.
  - `testOpeningAStoryMovesTheFrameWithoutAScroll` (Review Focus 1): only if the seed has a story on the spine; if not, add one two-moment story to `writeSpine` at the end of the function and say so in the report. Opening it changes the "On screen" years to those now visible.
  - `testWithNoDatedMomentThereIsNoCard`: with a seed that has no dated moment (check `UITestSeed`; if none exists, launch first-open-done with `-uiTesting-seed` and assert on whatever it holds, stating which in the report), `timeline.card` does not exist and `timeline.chapters` in the "…" menu still opens the life map.
  - `testAtTheLargestTextTheCardAndTheListAreReachable` (Review Focus 5): with `UICTContentSizeCategoryAccessibilityXXXL`, the card is hittable, the first spine row is hittable after at most one swipe, and the card's height is under half the screen.
- [ ] **Step 2: Prove two tests can fail:** break an expected value in two tests, run each, record the failure, restore.
- [ ] **Step 3: Run** `TimelineCardUITests`, `SpineUITests`, `TimelineUITests`, `ChaptersUITests`. Expected: pass.
- [ ] **Step 4: Commit** `UI tests for the pinned card: strip, frame, During line`.

### Task 6: Docs, screenshots, the full run

**Files:**
- Modify: `docs/DECISIONS.md` (one entry at the top: the eight builder's defaults and every ruling), `docs/OVERVIEW.md` (the Timeline paragraph), `docs/specs/2026-11-16-timeline.md` (Status line: S6a, S6b and S6c built), `README.md` (Status)
- Create: `docs/plans/2026-11-18-timeline-card-device-check.md`, `docs/screenshots/timeline-card/`

- [ ] **Step 1: Write the device checklist.** It must include: the strip starts at the owner's birth year; each dated moment has a tick and a guessed one is hollow; the frame moves smoothly with a scroll and jumps with Reduce Motion on; the "During" line with the owner's own chapters after the owner states years for two that overlap; "+N" with many chapters; the card under VoiceOver reads one sentence; the largest text size; a drag on the strip does not scrub; the card over the waiting cards at the top and over the shelf at the end.
- [ ] **Step 2: Screenshots** on the simulator with the spine seed: before (`main`) and after at the top; after with a "During" line; after at the end of the list; after at the largest text size.
- [ ] **Step 3: Run** `swift test`, then the whole UI suite once. Record the counts in the ledger.
- [ ] **Step 4: Commit** `Docs: the Timeline's pinned card (S6b)`.

## After S6b

- The Things shelf and the Places menu use the computed periods (spec "Periods", rule 5).
- Carried from S6c: no sheet states a chapter with no end; the period names above the life map truncate at the largest text; the 6-second Undo under VoiceOver.
- Carried from S6a: the place on a row and the tap on a person or place; a softer gap label next to a guessed date.
- Carried from S6b: the frame can lag by one row at each edge of the list. A later task must give the top edge and the bottom edge their own slack.
- Carried from S6b: at the largest text size, the period label above an opened story is cut by a few points at the card's edge. A later task must scroll an opened story to clear the card.
- Carried from S6b: no UI test opens a story to move the frame. A later task must add a dated story to a seed and test it.
- Carried from S6b (R7): an open story's member rows do not move the frame. The story's own row decides. A later task must give each member row its own years and its own report, with its own test for the render loop.
- Carried from S6b (R7): a confirmed relation's row has a tick and no years, so it does not move the frame. A later task must decide which years it gives the frame.
- Carried from S6b (R8): `CardSource` does not keep the strip. The card builds it again when the rows on screen change. A later task must keep it until the moments change.
- Carried from S6b (R8): `screenArea` is `@State` on `TimelineScreen`. A change of the list's frame redraws the screen's body. A later task must decide if it moves out of the screen's state.
- Carried from S6b (R8): at the accessibility sizes the "During" line is always two lines tall, also when the names fit on one line. A later task must decide if it can shrink to one line.
- Carried from S6b (R8): the "During" line and the slack use the height of a reference line in the names' font. A chapter name that is taller than that line can be cut, and the card can then change height by more than the slack. A later task must measure the names themselves.
- Carried from S6b: `LifeStripAxis.frameBox` has three edge cases and no unit test, because the app target has no unit tests. A later task must move the rule to the kit or add a test target.
- Carried from S6b: the card's margin is 16 points and the rows' margin is 12. A later task must pick one.
- Carried from S6b: `CivilDate.today().year` is a default in two places. A later task must keep it in one place.
- Carried from S6b: the mark placement in `LifeStrip` is one long line. `oneMomentIsOneMark` asserts a range, not the value. `aFrameIsClampedToTheStrip` asserts a range, not `0...0`. No frame test has no birth year. A later task must tighten these tests.
