# S7: The Things Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Things tab becomes a shelf. Tiles in two columns, one height, show a key photo with the title and the moment count, or the title and one quote in the person's words. Tiles group by life period from the thing's dated moments; the rest sit under "Not placed in time yet"; with no period the shelf is one flat grid. A tile placed by a guessed date says so.

**Architecture:** Tasks 1 and 2 are pure code in the kit: `ThingShelf.layout` (grouping, order, the guess flag) on the Timeline's own period rule, and `ThingQuote` with `ThingTileText` (the quote choice and the tile's words). Task 3 adds one batched read, `EntityRepository.details(type:)`, and `ExtractionStore.thingShelfSource()`, which reads everything the shelf needs in a fixed number of statements. Task 4 adds the screen, the tile, a thin view model, the seed and the UI tests, and puts the shelf in the Things tab. Task 5 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26 (`LazyVGrid`, `@ScaledMetric`), GRDB 7 (reads only), Swift Testing, XCUITest. No migration. No new dependency. No network call.

**Spec:** `docs/specs/2026-11-20-things-shelf.md` (all of it; the builder's defaults are numbered there and cited here as "default N"). It builds on `docs/specs/2026-11-15-five-sections.md` ("Things", "Life periods", "Photos", "Appearance and accessibility") and `docs/specs/2026-11-16-timeline.md` ("Periods"). The umbrella plan `docs/plans/2026-11-15-sections.md`, "Ship order" (S7, branch `sections-things`). `docs/DECISIONS.md`, entries of 2026-11-18 (S6c chapters, key photo, people and contacts) and 2026-11-16 (S6a, S4 photos, You). Mock-up: `docs/design/Sections.html`, the "Things" phone and its notes. Read these before Task 1.

**Worktree and branch:** `/Users/jakerosen/dev/lifeline/lifeline-things`, branch `sections-things`, based on `origin/main` (`aab2aa0`, which holds S1 to S4, S6a to S6c, the photo card and people with contacts). Work only there.

---

## Decisions made in this plan

The spec decides the design (its "Builder's defaults the owner can overrule", 1 to 15). These are the code decisions.

1. **One placing rule, shared with the spine.** `SpineLayout` gains `public static func placingDate(of: TimeRange) -> CivilDate?`: nil when the range is not dated; the likely start when the likely band has both ends; else the earliest date. `SpineLayout.stops` uses it for its period year, so the existing `SpineLayoutTests` guard the refactor. `ThingShelf` calls `LifePeriod.containing(year: placingDate.year, birthYear:)`. No second period rule exists.
2. **One heading text, shared with the spine.** `LifePeriod` gains `headingText` ("Teens · by your age", "The 1990s"). `SpineWaypoint` uses it in place of its private `suffix`. The Timeline's text does not change; `SpineUITests` and `ChaptersUITests` assert it today.
3. **A guess is an unsettled origin.** `placedByGuess` is true when no dated moment in the tile's period has `TimeRange.isSettled` (stated, confirmed, photo). The person's "around" is settled (spec, "A guess that decides the group").
4. **The quote rule lives in the kit.** `ThingQuote.choose` sorts the details itself (created at, then id), skips a detail whose first telling is in a heavy session, and returns the first `EntityPage.ownWordsQuote(of:maxWords: 20)` that is not nil.
5. **The tag filter menu becomes generic.** `EntityTagFilterMenu` takes any `TagFiltering` model (`allTags`, `tagFilter`). `EntitiesViewModel` and the new `ThingsShelfViewModel` conform. People and Places do not change.
6. **The shelf has its own view model.** `EntitiesViewModel` stays for People and Places. `ThingsShelfViewModel` reads `thingShelfSource()`, applies the tag filter, and calls the pure functions. It holds no rule.
7. **The tile keeps `entities.row`.** `EntitiesUITests` and `KindsUITests` find things by `entities.row` and their label, and wait on `navigationBars["Things"]`. The tile's label is the title, so they pass unchanged.
8. **A seed and its own simulator.** `-uiTesting-seedThings` writes the invented shelf below. `-uiTesting-thingsUndatedOnly` writes only its undated things. The simulator is "Lifeline Things", id `1F1457A7-1ED7-4149-A2BB-C0C2A9E76435`.

### Where the spec did not fit the code

The spec lists these under its section of the same name: a chapter is no longer a period; a thing can have a stated span; "about" is the `detail` relation; "dated" is `isDated`; the spine places stories and collection moments differently; the mock-up predates S6c; the tag filter stays. This plan adds one:

- `EntityListScreen` stays. Places still uses it. Only the `.thing` case in `SectionsScreen.root(of:)` changes.

### Limits found while planning

- **S5 (search) is not merged.** It adds `.searchButton(deps:)` to every tab root in `SectionsScreen` and a `.topBarLeading` toolbar item. The shelf puts its tag filter at the default placement, never at `.topBarLeading`. At merge, keep both sides in `SectionsScreen.swift`, `Dependencies.swift`, `UITestSeed.swift` and `UITestHelpers.swift`; then run `ThingsUITests` and `SearchUITests`. Search adds `XCUIApplication.waitForLabel(_:_:timeout:)` to `UITestHelpers.swift`. This plan adds no helper of that name: `ThingsUITests` has its own private `waitForBarLabel`.
- To keep the merge small, put the seed's launch line after the `-uiTesting-seedPhotos` block in `Dependencies.swift`, and `writeThings` after `writePhotos` in `UITestSeed.swift`. Search edits the lines after `-uiTesting-seedSpine` and `SeedSession.keep`. This plan does not change `SeedSession.keep`.
- No seed has a heavy session that UI tests can open as a detail. The heavy-session rule has kit tests only (Task 2).
- Dark and increased-contrast colour values still have no PR. S7 adds no colour value.

---

## Global Constraints

- Deployment target iOS 26.0. Swift 6 with complete strict concurrency.
- No migration. `Migrations.swift` and `MigrationsTests.swift` do not change. Backup and restore do not change.
- **Privacy and no nag.** No network call. No new count that reads as a to-do: no number of things, no number of unplaced things. No "add" control and no empty photo slot on the shelf. New code must not log or persist a title or a quote. Each task ends with `git grep -nE "print\(|Logger|os_log|NSLog|URLSession|UserDefaults|AppStorage|SceneStorage" -- <the task's new files>`, which must print nothing.
- Nothing inferred shows as fact (non-negotiable 3, P5). A tile never shows a year range or a date.
- Copy, exact: "Not placed in time yet"; "{name} · by your age"; "1 moment"; "{n} moments"; "Placed by a guess" **(invented copy)**; "Nothing yet. They appear as you tell stories."; "Nothing tagged “{tag}”."; "Could not show your things: {reason}" **(invented copy)**. The person reads "key photo", never "cover".
- Pure logic lives in `LifelineKit/Domain/` with Swift Testing tests. One responsibility for each file. New `Domain/` enums have no raw string values.
- The view model does no read in `init`, exposes `isLoaded`, and reads in a fixed number of statements.
- Text colours: `Theme.ink`, `Theme.secondaryText`, `Theme.ochreText`. Headings use `sectionHeadingStyle()` and carry `.isHeader`. Every text colour reaches 4.5:1 on linen, sand and card. A guess is a word, never a colour alone.
- Every control is at least 44 by 44 points. Text uses text styles, so it follows Dynamic Type.
- Keep these accessibility identifiers: `tab.things`, `entities.row`, `entities.tagFilter`, `entities.tag.{tag}`, `home.start`, `entity.title`, `timeline.period`. New ones: `things.grid`, `things.period`, `things.unplaced`, `things.empty`, `things.error`.
- Kit tests: `cd ios/LifelineKit && swift test`. They run in full at every task. `ExtractionQueueTests.drainGivesUpAtItsDeadline`, `SegmentPlayerTests.playStartsAtRangeStartAndStopsAtRangeEnd` and `CascadeVoiceSessionTests.pausesAreLoggedNotEmitted` are timing tests that can fail under load; run a failed one alone before you call it a failure.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'platform=iOS Simulator,id=1F1457A7-1ED7-4149-A2BB-C0C2A9E76435' -only-testing:LifelineUITests/<Class>`. Run `xcodegen generate` after you add a file. Each task names its classes. The report gives the verbatim `Executed N tests, with M failures` line for each. `YouUITests.testAPlayErrorLeavesAnOpenUndoInPlace` can fail under load; run it alone before you call it a failure. The whole UI suite runs once, by the controller, after the final review.
- Real TDD: each new test is seen failing before the code that makes it pass.
- No test's assertion is weakened. No existing test asserts the list rows' span line on Things.
- Fixtures are invented; never a real person's words, names or places.
- `ios/Config/Local.xcconfig` is untracked and is never committed.
- Commit messages are imperative and one line, with a body when the why is not obvious. No AI attribution lines. Nothing is pushed.
- Docs under `docs/` use ASD-STE100 style.

## Review Focus

1. **A guess never reads as a fact.** An inferred date that decides the group gives "Placed by a guess"; a settled moment in the same period clears it; the person's "around" does not give it. Task 1 (`aGuessedDateMarksTheTile`, `aSettledMomentInThePeriodClearsTheMark`, `thePersonsOwnAroundIsNotAGuess`) and Task 4 (`testAGuessedDateSaysSo`).
2. **Hidden stays hidden.** A hidden thing is not a tile; a hidden memory gives no quote and no date. Task 3 (`aHiddenOrUntoldDetailIsNotRead`, `theShelfSourceLeavesAHiddenThingAndItsKeyPhotoOut`) and Task 4 (`testAHiddenThingIsNotOnTheShelf`, `testAHiddenMemoryGivesNoQuoteAndNoPlace`).
3. **A thing in two periods.** It shows once, in the earlier one, and that period comes first. Task 1 (`aThingSitsOnceInThePeriodOfItsEarliestDatedMoment`) and Task 4 (`testAThingShowsOnceInItsFirstPeriod`).
4. **The quote is the person's words, cleaned, and safe.** Filler-only details are skipped; a heavy session never gives the quote; a long quote is cut. Task 2 (`aDetailOfOnlyFillerIsSkipped`, `aDetailFromAHeavySessionIsNotChosen`, `aLongQuoteIsCutAtTwentyWords`) and Task 4 (`testATileWithoutAPhotoShowsTheQuote`).
5. **The largest text and VoiceOver.** One column, nothing cut, one button per tile with its value. Task 4 (`testTheLargestTextIsOneColumnAndALongTitleWraps`, `testATileReadsAsOneButton`).

---

### Task 1: Kit — group and order the shelf on the spine's period rule

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/ThingShelf.swift`
- Modify: `ios/LifelineKit/Sources/LifelineKit/Domain/SpineLayout.swift` (`placingDate(of:)`; `stops` uses it for its period year)
- Modify: `ios/LifelineKit/Sources/LifelineKit/Domain/LifePeriod.swift` (`headingText`)
- Modify: `ios/Lifeline/Screens/Timeline/SpineRowView.swift` (`SpineWaypoint` uses `period.headingText`; its private `suffix` goes)
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/ThingShelfTests.swift`; add two tests to `SpineLayoutTests.swift` and one to `LifePeriodTests.swift`

**Interfaces:**
- Consumes: `EntitySummary` (`entity.range`, `momentRanges`, `id`), `LifePeriod.containing(year:birthYear:)`, `TimeRange.isDated`, `TimeRange.isSettled`, `CivilDate` (Comparable).
- Produces:

```swift
extension SpineLayout {
    /// The date the spine starts a dated range at: the likely start when the likely band has both ends, else the earliest. Nil when not dated.
    public static func placingDate(of range: TimeRange) -> CivilDate?
}
extension LifePeriod {
    /// "Teens · by your age" for a period by age; "The 1990s" for a decade.
    public var headingText: String { get }
}
/// The Things shelf: which group each thing sits in, and in what order. Pure.
public enum ThingShelf {
    public struct Tile: Sendable, Equatable, Identifiable {
        public var summary: EntitySummary
        /// No dated moment in this tile's period is settled. False for a stated span and for an unplaced tile.
        public var placedByGuess: Bool
        public var id: EntityID { get }
        public init(summary: EntitySummary, placedByGuess: Bool)
    }
    public enum Heading: Sendable, Equatable {
        case period(LifePeriod), notPlaced
        /// `headingText` of the period, or "Not placed in time yet".
        public var text: String { get }
    }
    public struct Group: Sendable, Equatable { public var heading: Heading; public var tiles: [Tile]; public init(heading: Heading, tiles: [Tile]) }
    public enum Layout: Sendable, Equatable { case flat([Tile]), grouped([Group]) }
    /// Spec "Grouping by period", "The flat grid" and "Order". `things` holds visible things only.
    public static func layout(_ things: [EntitySummary], birthYear: Int?) -> Layout
}
```

- [ ] **Step 1: Write the failing tests**

```swift
// ThingShelfTests.swift. Invented things and years only. Birth year 1990 unless a test says otherwise.
private func said(_ y: Int) -> TimeRange { .stated(year: y) }
private func guess(_ y: Int) -> TimeRange { .year(y, origin: .inferred, evidence: nil) }
private func thing(_ title: String, _ moments: [TimeRange] = [], stated: TimeRange = .unplaced) -> EntitySummary {
    EntitySummary(entity: Entity(id: EntityID(rawValue: title), type: .thing, title: title, range: stated),
                  ownWords: nil, momentRanges: moments, span: stated)
}
/// The titles of each group, top to bottom; one array for `.flat`.
private func titles(_ layout: ThingShelf.Layout) -> [[String]]
/// `Heading.text` of each group; empty for `.flat`.
private func headings(_ layout: ThingShelf.Layout) -> [String]
/// The tile with this title, in any group.
private func tile(_ title: String, in layout: ThingShelf.Layout) -> ThingShelf.Tile?

@Test func aThingSitsOnceInThePeriodOfItsEarliestDatedMoment() {
    let layout = ThingShelf.layout([thing("The red bike", [said(2004), said(1999)])], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age"])
    #expect(titles(layout) == [["The red bike"]], "not again under Teens")
}
@Test func groupsRunInLifeOrderAndNotPlacedComesLast() {
    let layout = ThingShelf.layout([thing("The radiator", [guess(2012)]), thing("Grandpa's watch", [.unplaced]), thing("The red bike", [said(1999)])], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age", "Twenties · by your age", "Not placed in time yet"])
}
@Test func tilesInAPeriodRunByPlacingDateThenTitle() {
    let layout = ThingShelf.layout([thing("Dad's Volvo", [said(2001)]), thing("The red bike", [said(1999)]),
                                    thing("another bike", [said(1999)]), thing("The piano", stated: .stated(between: 1996, and: 2002))], birthYear: 1990)
    #expect(titles(layout) == [["The piano", "another bike", "The red bike", "Dad's Volvo"]])
}
@Test func notPlacedRunsByTitleIgnoringCase() {
    let layout = ThingShelf.layout([thing("the guitar"), thing("The blue kite", [.unplaced]), thing("Grandpa's watch"), thing("The red bike", [said(1999)])], birthYear: 1990)
    #expect(titles(layout).last == ["Grandpa's watch", "The blue kite", "the guitar"])
}
@Test func twoThingsWithOneTitleKeepAnOrderById() {
    let a = EntitySummary(entity: Entity(id: EntityID(rawValue: "a"), type: .thing, title: "The box"), ownWords: nil, momentRanges: [], span: .unplaced)
    let b = EntitySummary(entity: Entity(id: EntityID(rawValue: "b"), type: .thing, title: "The box"), ownWords: nil, momentRanges: [], span: .unplaced)
    guard case .flat(let tiles) = ThingShelf.layout([b, a], birthYear: 1990) else { Issue.record("flat"); return }
    #expect(tiles.map(\.id.rawValue) == ["a", "b"])
}
@Test func withNoPlacedThingTheShelfIsFlat() {
    let watch = thing("Grandpa's watch", [.unplaced]), guitar = thing("The guitar")
    #expect(ThingShelf.layout([guitar, watch], birthYear: 1990)
            == .flat([ThingShelf.Tile(summary: watch, placedByGuess: false), ThingShelf.Tile(summary: guitar, placedByGuess: false)]))
}
@Test func noThingIsAnEmptyFlatShelf() {
    #expect(ThingShelf.layout([], birthYear: 1990) == .flat([]))
}
@Test func aStatedSpanPlacesAThingWithNoDatedMoment() {
    let layout = ThingShelf.layout([thing("The piano", [.unplaced], stated: .stated(between: 1996, and: 2002))], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age"])
    #expect(tile("The piano", in: layout)?.placedByGuess == false)
}
@Test func aDatedMomentBeatsTheStatedSpan() {
    let layout = ThingShelf.layout([thing("The piano", [said(2012)], stated: .stated(between: 1996, and: 2002))], birthYear: 1990)
    #expect(headings(layout) == ["Twenties · by your age"])
}
@Test func aGuessedDateMarksTheTile() {
    let layout = ThingShelf.layout([thing("The radiator", [guess(2012)]), thing("The red bike", [said(1999)])], birthYear: 1990)
    #expect(tile("The radiator", in: layout)?.placedByGuess == true)
    #expect(tile("The red bike", in: layout)?.placedByGuess == false)
}
@Test func aSettledMomentInThePeriodClearsTheMark() {
    #expect(tile("The kite", in: ThingShelf.layout([thing("The kite", [guess(1999), said(2001)])], birthYear: 1990))?.placedByGuess == false)
}
@Test func aGuessInAnEarlierPeriodDecidesAndKeepsItsMark() {
    let layout = ThingShelf.layout([thing("The kite", [said(2012), guess(2003)])], birthYear: 1990)
    #expect(headings(layout) == ["Teens · by your age"])
    #expect(tile("The kite", in: layout)?.placedByGuess == true)
}
@Test func thePersonsOwnAroundIsNotAGuess() {
    #expect(tile("The kite", in: ThingShelf.layout([thing("The kite", [.stated(around: 1999)])], birthYear: 1990))?.placedByGuess == false)
}
@Test func aPhotoDateIsNotAGuess() {
    #expect(tile("The kite", in: ThingShelf.layout([thing("The kite", [.fromPhoto(CivilDate(year: 1999, month: 7, day: 4)!)])], birthYear: 1990))?.placedByGuess == false)
}
@Test func withNoBirthYearPeriodsAreDecades() {
    let layout = ThingShelf.layout([thing("The radiator", [said(2012)]), thing("The red bike", [said(1999)])], birthYear: nil)
    #expect(headings(layout) == ["The 1990s", "The 2010s"])
}
@Test func aMomentBeforeBirthUsesItsDecadeAndComesFirst() {
    let layout = ThingShelf.layout([thing("The red bike", [said(1999)]), thing("Mum's radio", [said(1985)])], birthYear: 1990)
    #expect(headings(layout) == ["The 1980s", "Childhood · by your age"])
}
@Test func theLikelyBandDecidesThePeriodAsOnTheSpine() {
    let band = TimeRange(earliest: CivilDate(iso: "1998-01-01"), latest: CivilDate(iso: "2006-12-31"), likelyStart: CivilDate(iso: "2003-01-01"),
                         likelyEnd: CivilDate(iso: "2004-12-31"), granularity: .year, origin: .inferred, evidenceText: nil)
    #expect(headings(ThingShelf.layout([thing("The kite", [band])], birthYear: 1990)) == ["Teens · by your age"])
}
@Test func aHalfOpenRangePlacesNothing() {
    let halfOpen = TimeRange(earliest: CivilDate(iso: "1999-01-01"), latest: nil, likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .stated, evidenceText: nil)
    let kite = thing("The kite", [halfOpen])
    #expect(ThingShelf.layout([kite], birthYear: 1990) == .flat([ThingShelf.Tile(summary: kite, placedByGuess: false)]))
}

// SpineLayoutTests.swift
@Test func placingDateIsTheLikelyStartWhenTheBandHasBothEnds() {
    let band = TimeRange(earliest: CivilDate(iso: "1998-01-01"), latest: CivilDate(iso: "2006-12-31"), likelyStart: CivilDate(iso: "2003-01-01"),
                         likelyEnd: CivilDate(iso: "2004-12-31"), granularity: .year, origin: .inferred, evidenceText: nil)
    #expect(SpineLayout.placingDate(of: band) == CivilDate(iso: "2003-01-01"))
}
@Test func placingDateIsTheEarliestOtherwiseAndNilWhenNotDated() {
    #expect(SpineLayout.placingDate(of: .stated(year: 1999)) == CivilDate(iso: "1999-01-01"))
    #expect(SpineLayout.placingDate(of: .unplaced) == nil)
}
// LifePeriodTests.swift
@Test func headingTextSaysByYourAgeOnlyForAnAgePeriod() {
    #expect(LifePeriod.containing(year: 2005, birthYear: 1990).headingText == "Teens · by your age")
    #expect(LifePeriod.containing(year: 2005, birthYear: nil).headingText == "The 2000s")
}
```

`titles`, `headings` and `tile` are three-line private helpers over the `Layout` cases. They hold no rule.

- [ ] **Step 2: Run `cd ios/LifelineKit && swift test --filter "ThingShelf|SpineLayout|LifePeriod"`.** Expected: FAIL; `ThingShelf`, `placingDate` and `headingText` do not exist.
- [ ] **Step 3: Implement.** For each thing, the placing ranges are its dated moments (`isDated`); with none, `[entity.range]` when that is dated; with neither, the tile goes to `.notPlaced`. The earliest placing range by `placingDate` decides the period. `placedByGuess` is `!placing.filter { period(of: $0) == thePeriod }.contains(where: \.isSettled)`, so a stated span gives false. Groups sort by their smallest placing year. Then change `SpineLayout.stops` to take its period year from `placingDate(of:)!.year`. Then change `SpineWaypoint` to `period.headingText`.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole kit suite, with every existing `SpineLayoutTests` test unchanged. Run `-only-testing:LifelineUITests/SpineUITests`. Expected: PASS. Run the privacy grep on `ThingShelf.swift`.
- [ ] **Step 5: Commit** — `Kit: group the Things shelf by the spine's own period rule`

### Task 2: Kit — the quote and the tile's words

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/ThingQuote.swift`, `ios/LifelineKit/Sources/LifelineKit/Domain/ThingTileText.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/ThingQuoteTests.swift`

**Interfaces:**
- Consumes: `Memory`, `Telling`, `SessionID`, `EntityPage.ownWordsQuote(of:maxWords:)` (which runs `ReadableQuote.text`).
- Produces:

```swift
/// The one quote a tile without a photo shows (spec defaults 3, 4 and 5). Pure.
public enum ThingQuote {
    public static let maxWords = 20
    /// `details`: told, visible details of one thing, in any order. Sorted here by `createdAt`, then id.
    /// A detail whose first telling is in a heavy session is skipped. The first cleaned quote that is not empty wins.
    public static func choose(details: [Memory], tellings: [MemoryID: Telling], heavySessions: Set<SessionID>) -> String?
}
/// The words on a tile, and what VoiceOver reads. Pure.
public enum ThingTileText {
    public static let guessLine = "Placed by a guess"
    /// "1 moment", "3 moments"; nil for 0.
    public static func countLine(_ moments: Int) -> String?
    /// The count, the guess line and the quote in curly quotes, joined by ". ". Empty when there is none.
    public static func accessibilityValue(moments: Int, placedByGuess: Bool, quote: String?) -> String
}
```

- [ ] **Step 1: Write the failing tests**

```swift
private func detail(_ id: String, _ quote: String, at n: Int) -> Memory {
    Memory(id: MemoryID(rawValue: id), title: id, summaryQuote: quote, visibility: .timeline, chapterID: nil,
           createdFromCandidateID: CandidateID(rawValue: "c-\(id)"), createdAt: Date(timeIntervalSince1970: Double(n)), kind: .fact)
}
private func told(in session: String) -> Telling {
    Telling(sessionID: SessionID(rawValue: session), audioPath: "seed.m4a", range: MsRange(start: 0, end: 4_000), toldAt: .now)
}

@Test func theQuoteIsTheOldestToldDetailCleaned() {
    let quote = ThingQuote.choose(details: [detail("b", "the seats were green", at: 2), detail("a", "um, it smelled like oranges and wet dog", at: 1)],
                                  tellings: [:], heavySessions: [])
    #expect(quote == "It smelled like oranges and wet dog")
}
@Test func aDetailOfOnlyFillerIsSkipped() {
    #expect(ThingQuote.choose(details: [detail("a", "um, uh", at: 1), detail("b", "the seats were green", at: 2)], tellings: [:], heavySessions: []) == "The seats were green")
}
@Test func aDetailFromAHeavySessionIsNotChosen() {
    let details = [detail("a", "he clanked all night", at: 1), detail("b", "the seats were green", at: 2)]
    #expect(ThingQuote.choose(details: details, tellings: [MemoryID(rawValue: "a"): told(in: "heavy")], heavySessions: [SessionID(rawValue: "heavy")]) == "The seats were green")
    #expect(ThingQuote.choose(details: details, tellings: [MemoryID(rawValue: "a"): told(in: "calm")], heavySessions: [SessionID(rawValue: "heavy")]) == "He clanked all night")
}
@Test func noDetailGivesNoQuote() {
    #expect(ThingQuote.choose(details: [], tellings: [:], heavySessions: []) == nil)
    #expect(ThingQuote.choose(details: [detail("a", "um, uh", at: 1)], tellings: [:], heavySessions: []) == nil)
}
@Test func aLongQuoteIsCutAtTwentyWords() {
    let long = (1...30).map { "w\($0)" }.joined(separator: " ")
    #expect(ThingQuote.choose(details: [detail("a", long, at: 1)], tellings: [:], heavySessions: [])
            == "W1 " + (2...20).map { "w\($0)" }.joined(separator: " ") + "…")
}
@Test func countLineSaysMomentsAndNothingForNone() {
    #expect(ThingTileText.countLine(0) == nil)
    #expect(ThingTileText.countLine(1) == "1 moment")
    #expect(ThingTileText.countLine(3) == "3 moments")
}
@Test func accessibilityValueJoinsWhatTheTileShows() {
    #expect(ThingTileText.accessibilityValue(moments: 1, placedByGuess: true, quote: "He clanked all night") == "1 moment. Placed by a guess. “He clanked all night”")
    #expect(ThingTileText.accessibilityValue(moments: 0, placedByGuess: false, quote: "I never learned more than three chords") == "“I never learned more than three chords”")
    #expect(ThingTileText.accessibilityValue(moments: 2, placedByGuess: false, quote: nil) == "2 moments")
    #expect(ThingTileText.accessibilityValue(moments: 0, placedByGuess: false, quote: nil) == "")
}
```

- [ ] **Step 2: Run `swift test --filter "ThingQuote"`.** Expected: FAIL; the types do not exist.
- [ ] **Step 3: Implement.** Sort by `(createdAt, id.rawValue)`. A detail with no entry in `tellings` is not skipped. Call `EntityPage.ownWordsQuote(of:maxWords: maxWords)`; do not call `ReadableQuote` a second way.
- [ ] **Step 4: Run `swift test`.** Expected: PASS. Run the privacy grep on the two new files.
- [ ] **Step 5: Commit** — `Kit: a thing's tile quotes the oldest detail, cleaned, never from a heavy session`

### Task 3: Store — everything the shelf reads, in a fixed number of statements

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/EntityRepository.swift` (`details(type:)`, placed after `aboutLinks(kinds:)`, away from the lines S5 edits)
- Create: `ios/LifelineKit/Sources/LifelineKit/Store/ThingShelfReads.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/ThingShelfReadsTests.swift`

**Interfaces:**
- Consumes: `EntityRepository.summaries(type:)`, `PhotoRepository.covers(type:)`, `ProfileRepository.ownerBirthDate()`, `MemoryRepository.firstTellings(kinds:)`, `SessionRepository.heavySessionIDs()`.
- Produces:

```swift
extension EntityRepository {
    /// Told, visible memories linked to each entity of a type by `detail`, oldest told first (`created_at`, then id).
    /// One statement. An entity with none is absent. Hidden entities are not filtered: pair it with `entities(type:)`.
    public func details(type: EntityType) throws -> [EntityID: [Memory]]
}
/// What the Things shelf shows, read in a fixed number of statements (S7).
public struct ThingShelfSource: Sendable {
    public var birthYear: Int?
    /// Visible things, from `summaries(type: .thing)`.
    public var things: [EntitySummary]
    /// The key photo of each visible thing.
    public var keyPhotos: [EntityID: Photo]
    public var details: [EntityID: [Memory]]
    /// The first telling of every told, visible memory, for the heavy-session rule.
    public var tellings: [MemoryID: Telling]
    public var heavySessions: Set<SessionID>
}
extension ExtractionStore {
    public func thingShelfSource() throws -> ThingShelfSource
}
```

- [ ] **Step 1: Write the failing tests**

Copy `StatementCounter` from `EntityBatchReadsTests.swift` (it is private there) and the `photo(_:at:)` helper from `PhotoRepositoryTests.swift`. Build memories with `StoreFixtures.session(in:segments:)` and `StoreFixtures.memory(in:candidates:segment:title:createdAt:)`, one segment per memory.

```swift
@Test func detailsAreReadForEveryEntityOfATypeOldestToldFirst() throws {
    // bike: facts "B" (told at 2) and "A" (told at 1), both linked by detail. guitar: fact "C".
    let details = try f.store.entities.details(type: .thing)
    #expect(details[bike.id]?.map(\.title) == ["A", "B"])
    #expect(details[guitar.id]?.map(\.title) == ["C"])
}
@Test func aHiddenOrUntoldDetailIsNotRead() throws {
    // bike: a hidden fact and a floating stand-in (no candidate), both linked by detail
    #expect(try f.store.entities.details(type: .thing)[bike.id] == nil)
}
@Test func aMentionIsNotADetail() throws {
    // bike: one moment linked by mention
    #expect(try f.store.entities.details(type: .thing)[bike.id] == nil)
}
@Test func detailsOfAnotherTypeAreNotRead() throws {
    // Maya (person): a fact linked by detail
    #expect(try f.store.entities.details(type: .thing).isEmpty)
}
@Test func theShelfSourceLeavesAHiddenThingAndItsKeyPhotoOut() throws {
    // bike and box, each with a key photo (`photos.insert(_:linkingTo: .entity(id))`); box hidden
    let source = try f.store.thingShelfSource()
    #expect(source.things.map(\.entity.title) == ["The red bike"])
    #expect(Set(source.keyPhotos.keys) == [bike.id])
}
@Test func theShelfSourceCarriesTheBirthYearTellingsAndHeavySessions() throws {
    // profile birth 1990-06-01; bike's fact told in the fixture session
    let source = try f.store.thingShelfSource()
    #expect(source.birthYear == 1990)
    #expect(source.tellings[fact.id]?.sessionID == sessionID)
    #expect(source.heavySessions.isEmpty)
}
@Test func theShelfSourceReadsInAFixedNumberOfStatements() throws {
    // as `summariesReadInAFixedNumberOfStatements`: 2 things with a fact, a moment and a key photo each, then 20
    #expect(statementsFor2 > 0)
    #expect(statementsFor20 == statementsFor2)
}
```

- [ ] **Step 2: Run `swift test --filter ThingShelfReads`.** Expected: FAIL; `details(type:)` and `thingShelfSource()` do not exist.
- [ ] **Step 3: Implement.** `details(type:)` is one `select memory.*, me.entity_id as link_entity_id from moment_entity me join entity … join memory …` with `me.relation = 'detail'`, `entity.type = ?` and `\(Self.toldAndVisible)`, ordered by `memory.created_at, memory.id`. `thingShelfSource()` calls the five reads listed under Consumes; `tellings` uses `memories.firstTellings(kinds: Set(MemoryKind.allCases))`.
- [ ] **Step 4: Run `swift test`.** Expected: PASS. Run the privacy grep on `ThingShelfReads.swift`.
- [ ] **Step 5: Commit** — `Store: the Things shelf reads in a fixed number of statements`

### Task 4: App — the shelf, its tiles, and the Things tab

**Files:**
- Create: `ios/Lifeline/Screens/Things/ThingsShelfScreen.swift`, `ios/Lifeline/Screens/Things/ThingTile.swift`, `ios/Lifeline/Screens/Things/ThingsShelfViewModel.swift`
- Modify: `ios/Lifeline/Screens/Shell/SectionsScreen.swift` (one line: `case .things: ThingsShelfScreen(deps: deps)`)
- Modify: `ios/Lifeline/Screens/Entities/EntityListScreen.swift` (`TagFiltering`; `EntityTagFilterMenu<Model: TagFiltering>`), `ios/Lifeline/Screens/Entities/EntitiesViewModel.swift` (conforms to `TagFiltering`)
- Modify: `ios/Lifeline/Dependencies.swift` (one block after `-uiTesting-seedPhotos`), `ios/Lifeline/UITestSeed.swift` (`writeThings`, after `writePhotos`)
- Modify: `ios/LifelineUITests/UITestHelpers.swift` (`launchWithThings`, `shelfTile(_:)`, `shelfLabels()`)
- Test: create `ios/LifelineUITests/ThingsUITests.swift`

**Interfaces:**
- Consumes: Task 1 `ThingShelf.layout`, `Heading.text`; Task 2 `ThingQuote.choose`, `ThingTileText`; Task 3 `thingShelfSource()`; `store.tags.all()`, `store.tags.elements(.entity, tagged:)`; `PhotoImageView(photo:size:cache:placeholder:)` with `.small`; `EntityScreen(viewModel:onChange:)`, `EntityViewModel(entity:deps:)`; `HomeViewModel.coverClosings`; `Theme`, `sectionHeadingStyle()`, `linenBackground()`.
- Produces:
  - `@MainActor protocol TagFiltering: AnyObject, Observable { var allTags: [String] { get }; var tagFilter: String? { get set } }`. `EntityTagFilterMenu<Model: TagFiltering>(viewModel: Model)`, body unchanged.
  - `@MainActor @Observable final class ThingsShelfViewModel: TagFiltering`: `init(deps: Dependencies)` (no read); `var tagFilter: String?` (`didSet` refreshes); `private(set) var layout: ThingShelf.Layout`; `private(set) var keyPhotos: [EntityID: Photo]`; `private(set) var quotes: [EntityID: String]`; `private(set) var allTags: [String]`; `private(set) var isLoaded: Bool`; `private(set) var error: String?`; `let deps: Dependencies`; `func refresh()`. `refresh()` reads `thingShelfSource()` and the tags, filters `things` by tag, then sets `layout = ThingShelf.layout(things, birthYear:)` and `quotes[id] = ThingQuote.choose(details: source.details[id] ?? [], tellings:, heavySessions:)`. On a thrown error: `error = "Could not show your things: \(error.localizedDescription)"`.
  - `ThingsShelfScreen(deps: Dependencies)`: owns the view model in `@State`. `.navigationTitle("Things")`, `.toolbar { EntityTagFilterMenu(viewModel:) }` at the default placement. Refresh on appear, on `home?.coverClosings` while visible, and from the page's `onChange`. States, in order: `error` → its line (`things.error`, red); loaded with no tile → the empty line (`things.empty`) with the existing copy, or "Nothing tagged “{tag}”."; `.flat` → one grid; `.grouped` → for each group a heading (`things.period` for a period, `things.unplaced` for "Not placed in time yet"; `sectionHeadingStyle()`, `.isHeader`) and a grid. Columns: two `GridItem(.flexible(), spacing: 12)`; one when `dynamicTypeSize.isAccessibilitySize`. A `ScrollView` with `LazyVStack`, identifier `things.grid`.
  - `ThingTile(tile: ThingShelf.Tile, keyPhoto: Photo?, quote: String?, deps: Dependencies, onChange: @escaping () -> Void)`: a `NavigationLink` to `EntityScreen`. `@ScaledMetric(relativeTo: .body) var height: CGFloat = 176`; the frame is that height except at accessibility sizes, where it is the content's height. With a key photo: `PhotoImageView(photo:size: .small, cache: deps.photoImages) { Theme.sand }` filling the top, then the title (`.system(.headline, design: .serif)`, `lineLimit(3)`) and `countLine` (footnote, `Theme.secondaryText`) on `Theme.card`. Without: `Theme.sand` fill, title `.system(.title3, design: .serif)` `lineLimit(3)`, the quote in curly quotes (`.system(.subheadline, design: .serif).italic()`, `lineLimit(4)`), then `countLine`. On both, when `placedByGuess`, `ThingTileText.guessLine` in footnote `Theme.ochreText`. Corner radius 14, clipped. At accessibility sizes `lineLimit(nil)`. One accessibility element: label the title, value `ThingTileText.accessibilityValue(...)`, identifier `entities.row`, `.contentShape(Rectangle())` inside the label. The photo is hidden from accessibility.
  - `UITestSeed.writeThings(store:profile:sessions:library:photosDirectory:undatedOnly:)`, under `-uiTesting-seedThings`, with `undatedOnly` from `-uiTesting-thingsUndatedOnly`. `photosDirectory` is `PhotoLocation.directory(under: root)` from `Dependencies.uiTesting()`. Jordan, born 1990-06-01. All invented. Moments use `keep(…, kind: .event, relation: .mention, links: [(thing, nil)])`; facts use `keep(…, kind: .fact, quote:, links: [(thing, nil)])` (the default relation is `.detail`).
    - "The red bike": moments "Riding to the quarry" (1999) and "Selling the red bike" (2004). A generated photo, rgb `0xC8893F`, added with `library.add(fileAt:assetLocalID:to: .entity(bike))`.
    - "Dad's Volvo": moment "The drive to Dayton" (2001); fact, quote "um, it smelled like oranges and wet dog".
    - "The piano": no moment; `store.entities.setStatedSpan(piano, .stated(between: 1996, and: 2002))`.
    - "The radiator": moment "The cold flat", then `updateRange(…, .year(2012, origin: .inferred, evidence: "when I was 22"))`; fact, quote "he clanked all night", then `setHidden(…, true)`.
    - "Grandpa's watch": undated moment "Grandpa's last visit". A generated photo, rgb `0x5F7046`, added to it; then its stored file `photosDirectory/<fileName>` is removed.
    - "The guitar": fact only, quote "I never learned more than three chords".
    - "The blue kite": moment "The kite in the tree" (2000), then `setHidden(…, true)`.
    - "The enormous green armchair that came with the flat on Hemenway Street": undated moment "Carrying the armchair upstairs".
    - "The shoebox": moment "The shoebox under the bed" (1999); then `store.entities.setHidden(shoebox, true)`.
    - With `undatedOnly`: only "Grandpa's watch" (without the photo) and "The guitar".
  - Expected shelf from the full seed, in reading order: "Childhood · by your age": "The piano", "The red bike", "Dad's Volvo"; "Twenties · by your age": "The radiator"; "Not placed in time yet": "Grandpa's watch", "The blue kite", "The enormous green armchair that came with the flat on Hemenway Street", "The guitar".
  - `XCUIApplication.launchWithThings(_ extra: [String] = [])` (launch arguments `-uiTesting -uiTesting-seedThings` plus `extra`; waits for `home.start`; then `openTab("Things")`). `shelfTile(_ title: String) -> XCUIElement`: the `entities.row` button with that label. `shelfLabels() -> [String]`: swipes up through `things.grid` and collects tile labels and heading labels in reading order until a swipe adds nothing (the grid is lazy).

- [ ] **Step 1: Write the failing UI tests**

```swift
final class ThingsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func waitForBarLabel(_ app: XCUIApplication, _ label: String) -> Bool { /* XCTNSPredicateExpectation on home.start, 5 s */ }

    @MainActor func testThingsIsAShelfGroupedByPeriod() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertEqual(app.shelfLabels(), ["Childhood · by your age", "The piano", "The red bike", "Dad's Volvo",
                                           "Twenties · by your age", "The radiator",
                                           "Not placed in time yet", "Grandpa's watch", "The blue kite",
                                           "The enormous green armchair that came with the flat on Hemenway Street", "The guitar"])
        XCTAssertTrue(app.navigationBars["Things"].exists)
    }
    @MainActor func testAThingShowsOnceInItsFirstPeriod() {
        let app = XCUIApplication.launchWithThings()
        let labels = app.shelfLabels()
        XCTAssertEqual(labels.filter { $0 == "The red bike" }.count, 1)
        XCTAssertFalse(labels.contains("Teens · by your age"), "its 2004 moment does not open a Teens group")
    }
    @MainActor func testATileWithAPhotoShowsThePhotoAndTheCount() {
        let app = XCUIApplication.launchWithThings()
        let bike = app.shelfTile("The red bike")
        XCTAssertTrue(bike.waitForExistence(timeout: 5))
        XCTAssertEqual(bike.value as? String, "2 moments")
        XCTAssertTrue(app.isNear(app.colour(of: bike, at: CGPoint(x: 0.5, y: 0.3)), 0xC8893F), "the key photo fills the top")
    }
    @MainActor func testATileWithoutAPhotoShowsTheQuote() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertEqual(app.shelfTile("Dad's Volvo").value as? String, "1 moment. “It smelled like oranges and wet dog”")
        XCTAssertEqual(app.shelfTile("The guitar").value as? String, "“I never learned more than three chords”", "a fact gives a quote, and no count")
        XCTAssertTrue(app.isNear(app.colour(of: app.shelfTile("Dad's Volvo"), at: CGPoint(x: 0.95, y: 0.05)), 0xECE3D2), "the sand face")
    }
    @MainActor func testAGuessedDateSaysSo() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertEqual(app.shelfTile("The radiator").value as? String, "1 moment. Placed by a guess")
        XCTAssertFalse((app.shelfTile("The red bike").value as? String ?? "").contains("guess"))
    }
    @MainActor func testAHiddenMemoryGivesNoQuoteAndNoPlace() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertFalse((app.shelfTile("The radiator").value as? String ?? "").contains("clanked"), "the hidden fact gives no quote")
        XCTAssertEqual(app.shelfTile("The blue kite").value as? String ?? "", "", "the hidden moment gives no count and no period")
    }
    @MainActor func testAHiddenThingIsNotOnTheShelf() {
        XCTAssertFalse(XCUIApplication.launchWithThings().shelfLabels().contains("The shoebox"))
    }
    @MainActor func testAPhotoThatCannotLoadKeepsTheTile() {
        let app = XCUIApplication.launchWithThings()
        let watch = app.shelfTile("Grandpa's watch")
        XCTAssertTrue(app.reveal(watch))
        XCTAssertEqual(watch.value as? String, "1 moment")
        XCTAssertTrue(app.isNear(app.colour(of: watch, at: CGPoint(x: 0.5, y: 0.3)), 0xECE3D2), "sand where the photo would be")
    }
    @MainActor func testTilesInARowAreOneHeight() {
        let app = XCUIApplication.launchWithThings()
        let piano = app.shelfTile("The piano"), bike = app.shelfTile("The red bike")
        XCTAssertTrue(piano.waitForExistence(timeout: 5))
        XCTAssertEqual(piano.frame.minY, bike.frame.minY, accuracy: 1)
        XCTAssertEqual(piano.frame.height, bike.frame.height, accuracy: 1)
        XCTAssertLessThan(piano.frame.maxX, bike.frame.minX, "two columns")
    }
    @MainActor func testATapOpensThePageAndTheBarNamesIt() {
        let app = XCUIApplication.launchWithThings()
        app.shelfTile("The red bike").tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "The red bike")
        XCTAssertTrue(waitForBarLabel(app, "Tell a story about The red bike"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Things"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForBarLabel(app, "Tell a story"))
    }
    @MainActor func testTheShelfIsFlatWithNoPlacedThing() {
        let app = XCUIApplication.launchWithThings(["-uiTesting-thingsUndatedOnly"])
        XCTAssertTrue(app.shelfTile("Grandpa's watch").waitForExistence(timeout: 5))
        XCTAssertFalse(app.any("things.period").exists)
        XCTAssertFalse(app.any("things.unplaced").exists, "a flat grid has no heading")
    }
    @MainActor func testAnEmptyShelfSaysWhereThingsComeFrom() {
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting"]; app.launch(); app.skipFirstOpen(); app.openTab("Things")
        XCTAssertTrue(app.any("things.empty").waitForExistence(timeout: 5))
        XCTAssertEqual(app.any("things.empty").label, "Nothing yet. They appear as you tell stories.")
        XCTAssertFalse(app.buttons["entities.row"].exists)
    }
    @MainActor func testNoCountOrAddControlOnTheShelf() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertTrue(app.shelfTile("The piano").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Add")).count, 0)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "things you")).count, 0)
    }
    @MainActor func testATileReadsAsOneButton() {
        let app = XCUIApplication.launchWithThings()
        let volvo = app.shelfTile("Dad's Volvo")
        XCTAssertTrue(volvo.waitForExistence(timeout: 5))
        XCTAssertEqual(volvo.elementType, .button)
        XCTAssertEqual(volvo.label, "Dad's Volvo")
        XCTAssertFalse(volvo.staticTexts.firstMatch.exists, "the tile's texts are one element")
        XCTAssertFalse(volvo.images.firstMatch.exists, "no photo is described")
    }
    @MainActor func testTheLargestTextIsOneColumnAndALongTitleWraps() {
        let app = XCUIApplication.launchWithThings(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let piano = app.shelfTile("The piano"), bike = app.shelfTile("The red bike")
        XCTAssertTrue(piano.waitForExistence(timeout: 5) && app.reveal(bike))
        XCTAssertEqual(piano.frame.minX, bike.frame.minX, accuracy: 1, "one column")
        XCTAssertGreaterThanOrEqual(piano.frame.height, 44)
        let chair = app.shelfTile("The enormous green armchair that came with the flat on Hemenway Street")
        XCTAssertTrue(app.reveal(chair, swipes: 20))
        XCTAssertLessThanOrEqual(chair.frame.maxX, app.windows.firstMatch.frame.maxX)
    }
}
```

XCUITest cannot read the header trait. Device check item 6 covers the headings in the rotor.

- [ ] **Step 2: Create the simulator if `xcrun simctl list devices | grep "Lifeline Things"` prints nothing.** `xcrun simctl create "Lifeline Things" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-26-3`. Use id `1F1457A7-1ED7-4149-A2BB-C0C2A9E76435` when it exists.
- [ ] **Step 3: Run `cd ios && xcodegen generate`, then `-only-testing:LifelineUITests/ThingsUITests`.** Expected: FAIL; the Things tab is still the list (no `things.period`, no tile values).
- [ ] **Step 4: Implement as the Interfaces block says.** `SectionsScreen` changes only the `.thing` case. `EntityListScreen` stays for Places.
- [ ] **Step 5: Run `swift test`, then `-only-testing:LifelineUITests/ThingsUITests -only-testing:LifelineUITests/EntitiesUITests -only-testing:LifelineUITests/KindsUITests -only-testing:LifelineUITests/ShellUITests -only-testing:LifelineUITests/PeopleUITests -only-testing:LifelineUITests/SpineUITests`.** Expected: PASS. Run the privacy grep on `ios/Lifeline/Screens/Things`.
- [ ] **Step 6: Commit** — `Things: a shelf of tiles grouped by life period` (body: P1 for the person's words, P5 for "Placed by a guess", P9 for no count and no add control)

### Task 5: Docs, screenshots and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` (the Things section of "The shape of the app"; remove Things from "Designed, not built" if it is listed)
- Modify: `docs/DECISIONS.md` (one entry, newest first, dated the day it is written, in the shape of "2026-11-18 · S6b": Status with this plan and the ledger `.superpowers/sdd/2026-11-20-things-shelf/rulings.md`; the decision; the spec's fifteen builder's defaults, each with its cost; rulings made while building; Why; Consequences; Known costs. It supersedes the S4 line "No Timeline row, Things tile, search result or map uses a photo yet" for Things tiles.)
- Modify: `docs/design/README.md` (one line under "Sections (2026-11-15)": the Things phone in `Sections.html` predates S6c; the shelf is specified in `docs/specs/2026-11-20-things-shelf.md`)
- Create: `docs/plans/2026-11-20-things-shelf-device-check.md`
- Create: `docs/screenshots/things-shelf/before-things.png`, `after-shelf.png`, `after-not-placed.png`, `after-flat.png`, `after-empty.png`, `after-page-from-shelf.png`, `after-largest-text.png`

- [ ] **Step 1: Take the screenshots.** Before: `origin/main` in a temporary worktree (`git worktree add ../lifeline-things-before origin/main`), the Things tab with `-uiTesting -uiTesting-entities` after one recording, as `EntitiesUITests.launchAndRecord` does. After: this branch with `-uiTesting -uiTesting-seedThings`: the top of the shelf; "Not placed in time yet"; `-uiTesting-thingsUndatedOnly`; an empty archive; "The red bike" page opened from the shelf, with the bar; the shelf at `UICTContentSizeCategoryAccessibilityXXXL`. Use an uncommitted `ScreenshotTour.swift` in the UI test target that keeps each screen as an `XCTAttachment`, run it with `-resultBundlePath`, and export with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`. Remove the temporary worktree and delete `ScreenshotTour.swift`.
- [ ] **Step 2: Update OVERVIEW and the design README.**
- [ ] **Step 3: Add the DECISIONS entry.**
- [ ] **Step 4: Write the device checklist.** Each item is one line the owner ticks on the iPhone:
  1. Things opens on the shelf; the tiles in each row are one height; the title, count and quote read without clipping at the default text size.
  2. A thing with a key photo shows the photo; changing the key photo on its page changes the tile when you come back.
  3. A thing whose moment you dated by a guess shows "Placed by a guess"; after "Tell me when" with a year you say, the line goes.
  4. A thing whose page says "from 1996 to 2002" (Add dates) sits in that period, with no year range on the tile.
  5. A quote never shows filler words, and no quote comes from a session you stopped or where something hard was said.
  6. With VoiceOver: each tile is one button with its title, then its count, guess line and quote; the rotor's Headings move between the periods and "Not placed in time yet".
  7. At the largest accessibility text size: one column, every title in full, nothing cut.
  8. With Reduce Transparency and in dark appearance, the sand tiles and the ochre line stay readable.
  9. Start a story from the shelf; after it lands, a new thing from it appears without leaving the tab.
  10. The tag filter on Things still narrows the shelf, and "Everything" brings every tile back.
  11. In Airplane Mode the shelf looks the same.
- [ ] **Step 5: Run `swift test`.** Expected: PASS. Do not run the whole UI suite here; the controller runs it after the final review.
- [ ] **Step 6: Run the privacy grep over `ios/Lifeline/Screens/Things` and the four new kit files.** Expected: no output. Check that `git status` shows no `ios/Config/Local.xcconfig` and no `ScreenshotTour.swift`.
- [ ] **Step 7: Commit** — `Docs: the Things shelf in the overview, screenshots, and the device checklist`

---

## After S7

- **Owner's calls from use.** Whether a thing must show in every period it has a moment in (default 1). Whether the person must choose the quote (default 4). Whether "Placed by a guess" is the right words (default 7).
- **Quotes need detail links.** Most tiles have no quote until extractor v7 re-reads the archive and adds detail links.
- **Merge with S5.** See "Limits found while planning".
- S8 (Places) uses the same periods in its map menu. It can reuse `ThingShelf`'s placing rule through `SpineLayout.placingDate` and `LifePeriod.headingText`.
- The dark and increased-contrast colour values still have no PR assigned.
