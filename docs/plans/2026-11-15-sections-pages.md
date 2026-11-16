# S2: Entity Pages and the People Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** People becomes a grid of monogram tiles, and every person, place and thing page shows its life strip, what the person said about it, what it is often with, and its moments in order. All of this comes from batched reads of the tables that exist today.

**Architecture:** Task 1 adds batched reads to `EntityRepository`, so a list, a grid or a page uses a fixed number of queries. Tasks 2 and 3 add pure types in `Domain/` (`LifeStrip`, `ReadableQuote`, the page's sections and copy). Tasks 4 to 6 change the app: lists read in batches and pages load only when shown, the page gets its new layout, and People becomes a grid. Task 7 applies the quote cleanup to About and fixes olive text on bordered buttons. Task 8 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, GRDB 7 (no migration), Swift Testing, XCUITest.

**Spec:** `docs/specs/2026-11-15-five-sections.md`, sections "The life strip", "People", "Entity page (person, place, thing)", "Data" (the queries and `LifeStrip`) and "Appearance and accessibility". The UI audit `docs/specs/2026-10-26-ui-audit.md`, ship-order item 5 ("About and entity pages: details on pages, quote display and dates on people"), with findings F11 and F12. The umbrella plan `docs/plans/2026-11-15-sections.md`, Part 1 (ship order) and "After S1". Mock-ups: `docs/design/Sections.html`, the screens "People", "A page, with a photo" and "The same page, with little". Read the spec sections and the three mock-ups before Task 1.

**Worktree and branch:** `/Users/jakerosen/dev/lifeline/lifeline-pages`, branch `sections-pages`, based on `sections-shell` at `63c0463`. Work only there.

---

## Decisions made in this plan

The spec leaves these open. Each one is decided here so the owner can overrule it before work starts.

1. **No migration.** Every S2 need comes from `entity`, `moment_entity`, `memory`, `alias`, `person` and `profile`. v12 stays the last migration. If a later change in S2 needs a migration, its number is confirmed at implementation time, because another branch may take v13.
2. **What counts as a moment of an entity.** A memory of kind `event` or `other`, linked by relation `mention`, not hidden from the timeline, and told (it has a candidate; a floating stand-in is not told). The count in the sentence, the strip's marks, the grid's "Most told" order and the page's moment list all use this one rule. A fact, feeling or goal linked by `mention` shows with the details, under "What you've said about …".
3. **"Often with"** counts memories of kind `event` or `other`, not hidden and told, that link both entities by any relation. It needs two or more. It never lists the owner, an idea or a hidden entity. It links nothing new.
4. **Pronouns.** The details heading is "What you've said about them" for a person, "What you've said about it" for a place or a thing, and "What you've said about yourself" on the owner's page. The mock-up says "her", but the store holds no gender, and the app must not fill in a detail the person did not say.
5. **The sentence.** It reuses the wording of `EntityPage.spanText`. A said date reads "in 1995" or "from 1999 to 2003". A guess reads "around 1995" or "between 1999 and 2003". "most between 1999 and 2003" appears only when there are five or more dated moments and a window that holds at least two thirds of them spans at most half of the whole range. With any guess in it, that reads "most between about 1999 and 2003". One moment reads "In one moment"; more read "In 4 moments".
6. **The strip's axis.** It starts at the birth year, or at the subject's earliest dated moment when that is earlier or when there is no birth date. It ends at the current year. A mark sits at the centre of the moment's likely band, or of its possible band when it has no likely band, in whole years. A guessed mark is drawn hollow, so uncertainty is a shape and a word, not a colour. The axis shows two labels: its first year and "now".
7. **A stated span** (from "Add dates") shows as a span bar on the strip and as the line under the title (`entity.span`), as said. The derived span line leaves the page (audit F11: people carry dates).
8. **Own words.** A person's own words are their first alias that starts with "my " or "our ". With no such alias, the words are the role text the person used most often, but never the name itself or a bare pronoun. With neither, the tile keeps an empty line, so rows stay even.
9. **"First in your story"** orders people by their earliest dated moment. People with no dated moment come last. Ties go by name.
10. **The sort** starts on "Most told" at each launch. It is not remembered across launches, so UI tests do not leak state into each other.
11. **No people count.** The mock-up's subtitle "14 people in your story" is not in the spec. The grid omits it.
12. **Grid columns.** Three columns up to the largest standard text size. Two columns at accessibility sizes 1 and 2. A list at accessibility size 3 and larger.
13. **Tile tints.** The three tints from the mock-up: `0xE3DCC6`, `0xDDE2D3`, `0xEADBCB`. The tint index is the sum of the Unicode scalar values of the entity id, modulo 3. Swift's `hashValue` changes at every launch, so it must not be used.
14. **Page rows.** A detail shows its whole quote, cleaned for reading, with no line limit. A moment shows its date above its title, as in the mock-up and the spec's Timeline section. Empty sections do not show.
15. **A page with nothing in it** shows one line: "Stories you tell about {title} will show here." (owner: "Stories you tell about yourself will show here."). The record bar already names the page and starts the story.
16. **Lazy pages.** `EntityViewModel` and `EntitiesViewModel` do no reads in `init`. Each screen loads in `onAppear`. This is cheaper than value-based navigation, because `EntityScreen` is pushed from five stacks, including the landing cover, and each would need its own destination.
17. **About stays as it is in S2.** The audit says a fact about another person leaves About. `KindsUITests.testFactKeptLandsUnderAbout` pins today's About, with a fact about "the house". S3 rebuilds About as You's "Who you are", so the rule goes there. S2 delivers the other half of "details on pages": the fact shows on the page.
18. **Ideas** keep their "Over time" layout. Their "Beside it" section becomes "Often with", with the rule in decision 3.
19. **Quote cleanup** removes "um", "uh" and "erm"; "like" only when a comma follows it; "you know" only when a comma follows it or it ends the quote; and fragments made only of dashes and dots. A removed filler takes its trailing comma with it; a comma before it stays. A word said twice or more in a row (ignoring punctuation) keeps one copy, with no punctuation, except "had had" and "that that". A comma left at the end goes. The first letter is capitalised. The cleanup never changes the stored text, the memory page or the audio.
20. **Places and Things** keep their list rows (title and span), read in batches.
21. **Tags** stay at the bottom of every page.

### Conflicts and limits found while planning

- **Dark and increased-contrast values.** The spec says every colour gets a dark value and an increased-contrast value. `Theme` has neither today, and S1 did not add them. The new tints follow `Theme` as it is (light only). The owner must decide which PR adds the dark palette.
- **Thin data.** The audit counted 3 detail links in 37 memories. "Often with" will be empty on most pages, and many strips will be hidden, until extractor v7 re-reads the archive (track A). The page design accounts for this: an empty section does not show.
- **Out of S2's scope, by the ship order:** the photo header, the Photos row and "Add a photo" (S4); "Put on the map" and the small map (S8); the strip at the top of Timeline (S6); You as a portrait and About leaving Timeline (S3).
- **The record bar.** S2 does not touch `RecordBar`. The three-line refused-microphone state is left for the PR that next changes the bar.

---

## Global Constraints

- Deployment target iOS 26.0. Swift 6 with complete strict concurrency.
- No migration in this PR (decision 1). Never edit a shipped migration.
- Copy, exact:
  - Sort menu: "Most told", "First in your story", "By name".
  - Page headings: "What you've said about them", "What you've said about it", "What you've said about yourself", "Often with", "Moments with {title}", "Your moments".
  - Sentence: "In one moment", "In {n} moments", then ", in 1995", ", around 1995", ", from 1999 to 2003", ", between 1999 and 2003", ", most between 1999 and 2003" or ", most between about 1999 and 2003".
  - Invitation: "Stories you tell about {title} will show here." and "Stories you tell about yourself will show here."
  - "Often with" chip accessibility label: "{title}, {n} moments together".
  - Empty People tab: "Nothing yet. They appear as you tell stories." (unchanged).
- No screen asks the person to complete a record: no "add photo" mark, no empty field, no count of what is missing (PRINCIPLES 9).
- A guess never reads as fact: every inferred date in a sentence, a mark or a span carries "around", "between" or "about", or a hollow mark (PRINCIPLES 5, non-negotiable 3).
- "Often with" shows only what the person told. It creates no link (non-negotiable 3).
- The owner is never a tile and never in "Often with" (audit F10).
- The People grid and the lists must not run a query per tile or per row. A page must not run its reads until it is on screen.
- Secondary text is `Theme.secondaryText`. Text tinted olive is `Theme.oliveText`. `Theme.olive` is for fills and prominent buttons only. Every text colour reaches 4.5:1 on its surface.
- Every control is at least 44 by 44 points. Metadata uses the footnote text style or larger.
- Keep these accessibility identifiers: `entities.row`, `entities.tagFilter`, `entities.aboutYou`, `entity.title`, `entity.detail`, `entity.moment`, `entity.addTag`, `entity.tag`, `entity.more`, `entity.rename`, `entity.addDates`, `entity.play`, `home.start`, `home.people`, `people.more`.
- Kit tests: `cd ios/LifelineKit && swift test`. They run in full at every task.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`. Each task names the UI test classes it must run. Only those run during the task. The whole UI suite runs once, in Task 8.
- No test's assertions are weakened. A test that asserts old copy changes to the new copy and keeps an assertion of equal strength.
- `ios/Config/Local.xcconfig` is never committed.
- Commit messages are imperative and one line, with a body when the why is not obvious. No AI attribution lines. Nothing is pushed.
- Fixtures are invented. Never a real person's words.
- Every UI PR shows before and after simulator screenshots with invented data, under `docs/screenshots/sections-pages/` (Task 8).
- Docs under `docs/` use ASD-STE100 style.

## Review Focus

1. **A moment before the birth year** (a parent's story set in 1985, birth 1990): the axis starts at 1985 and the mark sits at the start, never off the strip. Task 2 (`aMomentBeforeBirthWidensTheAxis`).
2. **A tile's tint across launches:** the same person must keep the same tint after a relaunch. Swift's `hashValue` is seeded per launch. Task 6 (`theTintIsFixedByTheID`).
3. **A hidden memory or a floating stand-in** linked to a person: it must not count in "In N moments", in "Most told" or in "Often with". Task 1 (`hiddenAndUntoldMemoriesAreNotMoments`, `hiddenMemoriesAreNotShared`).
4. **The owner** is linked in most moments: the owner must not be a tile and must not lead "Often with". Task 1 (`theOwnerIsNeverOftenWith`) and Task 4 (`testTheSeedReachesEveryList`).
5. **The largest accessibility text size:** names must stay readable, so the grid becomes a list. Task 6 (`testTheGridBecomesAListAtTheLargestTextSize`).

---

### Task 1: Kit — batched entity reads

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/EntitySummary.swift` (`LinkedTime`, `CoOccurrence`, `EntitySummary`, `OwnWords`)
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/EntityRepository.swift` (a new `// MARK: - Batched reads` section; extract the span rule from `derivedSpan(of:)`)
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/EntityBatchReadsTests.swift`

**Interfaces:**
- Consumes: `EntityRepository`, `Memory`, `MomentEntity`, `TimeRange`, `PeopleRepository.relationLabel(aliases:)`, `PeopleRepository.normalize(_:)`.
- Produces:
  - `public struct LinkedTime: Sendable, Equatable { public var memoryID: MemoryID; public var range: TimeRange; public var isMoment: Bool }`. One per linked memory, distinct by memory. `isMoment` follows decision 2.
  - `public struct CoOccurrence: Sendable, Equatable { public var entity: Entity; public var sharedMoments: Int }`
  - `public struct EntitySummary: Sendable, Equatable, Identifiable { public var entity: Entity; public var ownWords: String?; public var momentRanges: [TimeRange]; public var span: TimeRange; public var momentCount: Int { get }; public var firstDate: CivilDate? { get }; public var id: EntityID { get } }`. `momentRanges` holds one range per moment, unplaced ones included, oldest told first. `span` is the stated span, else the derived one. `firstDate` is the earliest `likelyStart ?? earliest` over placed moment ranges.
  - `public enum OwnWords { public static func choose(title: String, aliases: [String], roleTexts: [String]) -> String? }` (decision 8).
  - On `EntityRepository`:
    - `public func strips(type: EntityType) throws -> [EntityID: [LinkedTime]]`: one query; an entity with no linked memory is absent.
    - `public func coOccurrences(of entity: EntityID, minimumShared: Int = 2) throws -> [CoOccurrence]`: one self-join on `moment_entity`; ordered by `sharedMoments` descending, then title ignoring case.
    - `public func ownWords(type: EntityType) throws -> [EntityID: String]` and `public func ownWords(of entity: EntityID) throws -> String?`: one query for aliases and one for role texts.
    - `public func summaries(type: EntityType) throws -> [EntitySummary]`: `entities(type:)` order (by title), built from the three reads above. Hidden entities are left out, as in `entities(type:)`.
    - `static func derivedSpan(over ranges: [TimeRange]) -> TimeRange`: today's rule from `derivedSpan(of:)`, which now calls it.

- [ ] **Step 1: Write the failing tests**

Build the fixture with `ExtractionStore(try AppDatabase.inMemory())` and `StoreFixtures`, as `EntityRepositoryTests.entityLinksAndSpans` does. Invented names: Maya, Dad, Sam, Lena, Alder Street, and the owner Jordan (save a `Profile` with `displayName: "Jordan"`).

```swift
@Test func stripsReadEveryEntityOfATypeAtOnce() throws {
    // Maya: m1 (event, 1999, mention), m2 (event, undated, mention), d1 (fact, 1995, detail). Dad: m1. Lena: nothing.
    let strips = try store.entities.strips(type: .person)
    #expect(strips[maya.id]?.count == 3)
    #expect(strips[maya.id]?.filter(\.isMoment).map(\.memoryID) == [m1.id, m2.id])
    #expect(strips[dad.id]?.map(\.memoryID) == [m1.id])
    #expect(strips[lena.id] == nil)
}
@Test func theBatchedSpanEqualsThePerEntitySpan() throws {
    let strips = try store.entities.strips(type: .person)
    for person in try store.entities.entities(type: .person) {
        #expect(EntityRepository.derivedSpan(over: strips[person.id, default: []].map(\.range)) == (try store.entities.derivedSpan(of: person.id)))
    }
}
@Test func hiddenAndUntoldMemoriesAreNotMoments() throws {
    // Maya: a hidden event (mention), a floating stand-in (createdFromCandidateID nil, mention), a fact (mention).
    #expect(try store.entities.strips(type: .person)[maya.id]!.filter(\.isMoment).isEmpty)
    #expect(try store.entities.summaries(type: .person).first { $0.entity.id == maya.id }?.momentCount == 0)
}
@Test func coOccurrencesCountSharedMomentsAndNeedTwo() throws {
    // Maya and Dad share m1, m2, m3; Maya and Alder Street share m1, m2; Maya and Sam share m4 only; the idea "hard work" shares m1, m2.
    #expect(try store.entities.coOccurrences(of: maya.id).map { "\($0.entity.title) \($0.sharedMoments)" } == ["Dad 3", "Alder Street 2"])
}
@Test func theOwnerIsNeverOftenWith() throws {
    // Jordan (the owner) is linked to m1, m2, m3 beside Maya.
    #expect(try !store.entities.coOccurrences(of: maya.id).contains { $0.entity.id == owner.entityID })
}
@Test func hiddenMemoriesAreNotShared() throws {
    // Maya and Sam also share two hidden events and one fact.
    #expect(try !store.entities.coOccurrences(of: maya.id).contains { $0.entity.id == sam.id })
}
@Test func ownWordsPreferARelationAliasThenTheCommonestRoleText() {
    #expect(OwnWords.choose(title: "Maya", aliases: ["Maya-bird", "my sister"], roleTexts: ["Maya"]) == "my sister")
    #expect(OwnWords.choose(title: "Dad", aliases: [], roleTexts: ["Dad", "my dad", "my dad", "he"]) == "my dad")
    #expect(OwnWords.choose(title: "Sam", aliases: [], roleTexts: ["sam ", "she", "Them"]) == nil)
    #expect(OwnWords.choose(title: "Lena", aliases: [], roleTexts: []) == nil)
}
@Test func summariesCarryCountsFirstDatesAndOwnWords() throws {
    let maya = try #require(try store.entities.summaries(type: .person).first { $0.entity.title == "Maya" })
    #expect(maya.momentCount == 2 && maya.firstDate?.year == 1999 && maya.ownWords == "my sister")
}
@Test func summariesReadInAFixedNumberOfStatements() throws {
    // Count statements with `db.writer.write { $0.trace { _ in counter.add() } }` on one in-memory AppDatabase.
    // Read summaries with 2 people, add 18 people with links, read again.
    #expect(statementsFor20 == statementsFor2)
}
```

- [ ] **Step 2: Run `cd ios/LifelineKit && swift test --filter EntityBatchReads`.** Expected: FAIL, the types and methods do not exist.
- [ ] **Step 3: Implement the types in `EntitySummary.swift` and the reads in `EntityRepository.swift`.** Moments in SQL: `memory.kind in ('event', 'other') and memory.hidden_from_timeline = 0 and memory.created_from_candidate_id is not null`, with `relation = 'mention'` for `isMoment`. The owner is `select id from person where is_owner = 1`. Bare pronouns for `OwnWords`: he, she, they, him, her, them, i, me, we, us, it.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole kit suite, `entityLinksAndSpans` included.
- [ ] **Step 5: Commit** — `Kit: read strips, own words and shared moments for a whole type at once`

### Task 2: Kit — the life strip

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/LifeStrip.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/LifeStripTests.swift`

**Interfaces:**
- Consumes: `TimeRange`, `EntityPage.spanText(_:)`.
- Produces:

```swift
public struct LifeStrip: Sendable, Equatable {
    public struct Mark: Sendable, Equatable { public var position: Double; public var isGuess: Bool }   // position in 0...1
    public let startYear: Int
    public let endYear: Int                       // the current year
    public let marks: [Mark]                      // dated moments only, in input order
    public let statedSpan: ClosedRange<Double>?   // positions; only when `stated` is placed
    public let sentence: String?                  // nil when there are no moments
    public var showsAxis: Bool { get }            // marks.count >= 2
    public init(moments: [TimeRange], stated: TimeRange = .unplaced, birthYear: Int?, currentYear: Int)
}
```

The algorithm (decisions 5 and 6), because the signature does not fix it:
- A moment's interval is `(likelyStart ?? earliest ?? latest)...(likelyEnd ?? latest ?? earliest)`. Its mark sits at `(Double(start.year) + Double(end.year) + 1) / 2`.
- `startYear = min(birthYear ?? .max, earliest dated start year)`. With neither, `startYear = currentYear`. A position is `(mid - startYear) / Double(currentYear + 1 - startYear)`, clamped to 0...1. The denominator is at least 1.
- A mark is a guess when its range's origin is neither `stated` nor `confirmed`.
- `statedSpan` is `(earliest.year - startYear) / d ... (latest.year + 1 - startYear) / d`, with `d` the same denominator, clamped to 0...1.
- The sentence is the count, then ", " and a phrase, when any moment is dated. For one dated moment, the phrase is `EntityPage.spanText(range)`. For two or more, it is `EntityPage.spanText` of a range from the smallest start year to the largest end year, with origin `stated` when every dated moment is said, else `inferred`. With five or more dated moments, take the start years. Find the narrowest window that holds at least `ceil(2 * n / 3)` of them. If its width is at most half of the whole range, the phrase is "most between {a} and {b}", or "most between about {a} and {b}" when any is a guess.

- [ ] **Step 1: Write the failing tests**

```swift
private func said(_ y: Int) -> TimeRange { .year(y, origin: .stated, evidence: "in \(y)") }
private func guess(_ y: Int) -> TimeRange { .year(y, origin: .inferred, evidence: nil) }

@Test func theSentenceCountsMoments() {
    #expect(LifeStrip(moments: [], birthYear: 1990, currentYear: 2026).sentence == nil)
    #expect(LifeStrip(moments: [.unplaced], birthYear: 1990, currentYear: 2026).sentence == "In one moment")
    #expect(LifeStrip(moments: [.unplaced, .unplaced, .unplaced], birthYear: 1990, currentYear: 2026).sentence == "In 3 moments")
}
@Test func oneDatedMomentSaysItsOwnDate() {
    #expect(LifeStrip(moments: [said(1995)], birthYear: 1990, currentYear: 2026).sentence == "In one moment, in 1995")
    #expect(LifeStrip(moments: [guess(1995)], birthYear: 1990, currentYear: 2026).sentence == "In one moment, around 1995")
    #expect(LifeStrip(moments: [.stated(between: 1996, and: 1999)], birthYear: 1990, currentYear: 2026).sentence == "In one moment, from 1996 to 1999")
}
@Test func severalDatedMomentsSayTheirRange() {
    let years = [1999, 2000, 2001, 2003]
    #expect(LifeStrip(moments: years.map(said), birthYear: 1990, currentYear: 2026).sentence == "In 4 moments, from 1999 to 2003")
    #expect(LifeStrip(moments: years.map(guess), birthYear: 1990, currentYear: 2026).sentence == "In 4 moments, between 1999 and 2003")
    #expect(LifeStrip(moments: [said(1999), said(2003), .unplaced], birthYear: 1990, currentYear: 2026).sentence == "In 3 moments, from 1999 to 2003")
}
@Test func aClusterSaysMost() {
    let years = [1992, 1999, 1999, 2000, 2001, 2001, 2002, 2003, 2003, 2010, 2016, 2020]
    #expect(LifeStrip(moments: years.map(said), birthYear: 1990, currentYear: 2026).sentence == "In 12 moments, most between 1999 and 2003")
    #expect(LifeStrip(moments: Array(years.map(said).dropLast()) + [guess(2020)], birthYear: 1990, currentYear: 2026).sentence == "In 12 moments, most between about 1999 and 2003")
}
@Test func marksSitOnTheAxisFromBirthToNow() {
    let strip = LifeStrip(moments: [said(1999), guess(2010), .unplaced], birthYear: 1990, currentYear: 2025)
    #expect(strip.startYear == 1990 && strip.endYear == 2025)
    #expect(strip.marks.count == 2 && strip.showsAxis)
    #expect(abs(strip.marks[0].position - 9.5 / 36) < 0.0001 && !strip.marks[0].isGuess)
    #expect(strip.marks[1].isGuess)
}
@Test func aMomentBeforeBirthWidensTheAxis() {
    let strip = LifeStrip(moments: [said(1985), said(2000)], birthYear: 1990, currentYear: 2025)
    #expect(strip.startYear == 1985 && strip.marks[0].position >= 0 && strip.marks[0].position < 0.05)
}
@Test func withNoBirthDateTheAxisStartsAtTheFirstMoment() {
    #expect(LifeStrip(moments: [said(2005), said(2012)], birthYear: nil, currentYear: 2025).startYear == 2005)
}
@Test func fewerThanTwoDatedMomentsHideTheAxis() {
    #expect(!LifeStrip(moments: [said(2012), .unplaced], birthYear: 1990, currentYear: 2025).showsAxis)
}
@Test func onlyAStatedSpanDrawsABar() {
    #expect(LifeStrip(moments: [said(1999), said(2001)], birthYear: 1990, currentYear: 2025).statedSpan == nil)
    let bar = LifeStrip(moments: [said(1999), said(2001)], stated: .stated(between: 1995, and: 2004), birthYear: 1990, currentYear: 2025).statedSpan
    #expect(bar.map { abs($0.lowerBound - 5.0 / 36) < 0.0001 && abs($0.upperBound - 15.0 / 36) < 0.0001 } == true)
}
```

- [ ] **Step 2: Run `swift test --filter LifeStrip`.** Expected: FAIL, `LifeStrip` does not exist.
- [ ] **Step 3: Implement `LifeStrip` as specified above.** It is pure and stores nothing.
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** — `Kit: a life strip that places moments and says them in words`

### Task 3: Kit — readable quotes and the page's sections

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/ReadableQuote.swift`
- Modify: `ios/LifelineKit/Sources/LifelineKit/Domain/EntityPage.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/ReadableQuoteTests.swift`; modify `EntityPageTests.swift`

**Interfaces:**
- Consumes: Task 1 `EntitySummary.momentCount`, `EntityRepository.summaries(type:)`.
- Produces:
  - `public enum ReadableQuote { public static func text(_ raw: String, maxWords: Int? = nil) -> String }` (decision 19). With `maxWords`, it cuts at a word boundary and ends with "…".
  - `public struct EntityPage.Sections: Sendable, Equatable { public var said: [Memory]; public var moments: [Memory] }`
  - `public static func EntityPage.sections(details: [Memory], mentions: [Memory]) -> EntityPage.Sections`. `said` holds the details and the mentions that are not moments, distinct by id, oldest told first. `moments` holds the mentions that are moments by decision 2, in `EntityPage.ordered(_:toldAt: [:])` order. Hidden and floating memories are in neither.
  - `public static func EntityPage.saidHeading(_ type: EntityType, isOwner: Bool) -> String`
  - `public static func EntityPage.momentsHeading(title: String, isOwner: Bool) -> String`
  - `public static func EntityPage.invitation(title: String, isOwner: Bool) -> String`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func fillerWordsAndRepeatsAreHidden() {
    #expect(ReadableQuote.text("we, we, -... spent a lot of time together, um, you know, a few summers") == "We spent a lot of time together, a few summers")
    #expect(ReadableQuote.text("um I was uh eight") == "I was eight")
    #expect(ReadableQuote.text("it was like, huge") == "It was huge")
    #expect(ReadableQuote.text("um, two years younger than me, you know") == "Two years younger than me")
    #expect(ReadableQuote.text("the the house had a blue door") == "The house had a blue door")
    #expect(ReadableQuote.text("and it rained, you know") == "And it rained")
}
@Test func wordsThatAreNotFillerStay() {
    #expect(ReadableQuote.text("I like dogs") == "I like dogs")
    #expect(ReadableQuote.text("it looked like a boat") == "It looked like a boat")
    #expect(ReadableQuote.text("you know what I mean") == "You know what I mean")
    #expect(ReadableQuote.text("I had had enough") == "I had had enough")
    #expect(ReadableQuote.text("") == "")
}
@Test func aLongQuoteEndsAtAWord() {
    #expect(ReadableQuote.text("one two three four five", maxWords: 3) == "One two three…")
    #expect(ReadableQuote.text("one two", maxWords: 3) == "One two")
}
@Test func thePageSplitsWhatWasSaidFromMoments() {
    // details: [d1 fact]; mentions: [m2 event 2001, m1 event 1999, f1 fact, h1 hidden event, s1 floating event, m3 event undated]
    let sections = EntityPage.sections(details: [d1], mentions: [m2, m1, f1, h1, s1, m3])
    #expect(sections.said.map(\.id) == [d1.id, f1.id])
    #expect(sections.moments.map(\.id) == [m1.id, m2.id, m3.id])
}
@Test func thePageCountsWhatTheGridCounts() throws {
    // Store fixture: Maya with the memories above, linked as named.
    let page = EntityPage.sections(details: try store.entities.details(of: maya.id), mentions: try store.entities.moments(of: maya.id))
    #expect(page.moments.count == (try store.entities.summaries(type: .person).first { $0.id == maya.id }?.momentCount))
}
@Test func headingsNeverGuessAGender() {
    #expect(EntityPage.saidHeading(.person, isOwner: false) == "What you've said about them")
    #expect(EntityPage.saidHeading(.place, isOwner: false) == "What you've said about it")
    #expect(EntityPage.saidHeading(.thing, isOwner: false) == "What you've said about it")
    #expect(EntityPage.saidHeading(.person, isOwner: true) == "What you've said about yourself")
    #expect(EntityPage.momentsHeading(title: "Sam", isOwner: false) == "Moments with Sam")
    #expect(EntityPage.momentsHeading(title: "Jordan", isOwner: true) == "Your moments")
    #expect(EntityPage.invitation(title: "Lena", isOwner: false) == "Stories you tell about Lena will show here.")
    #expect(EntityPage.invitation(title: "Jordan", isOwner: true) == "Stories you tell about yourself will show here.")
}
```

- [ ] **Step 2: Run `swift test --filter "ReadableQuote|EntityPage"`.** Expected: FAIL.
- [ ] **Step 3: Implement `ReadableQuote` and the `EntityPage` additions.** `ReadableQuote` works on tokens split at spaces, with punctuation attached to its word, and applies the rules of decision 19 in this order: fragments, fillers, repeats, the end comma, the capital.
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** — `Kit: quotes without filler words, and a page's details and moments`

### Task 4: App — lists read in batches, pages load when shown, an invented family to test with

**Files:**
- Modify: `ios/Lifeline/UITestSeed.swift` (add `writePeople`), `ios/Lifeline/Dependencies.swift:249-251` (the `-uiTesting-seedPeople` argument)
- Modify: `ios/Lifeline/Screens/Entities/EntitiesViewModel.swift`, `ios/Lifeline/Screens/Entities/EntityListScreen.swift` (`EntityRows`), `ios/Lifeline/Screens/You/YouScreen.swift`, `ios/Lifeline/Screens/Entities/EntityViewModel.swift` (`init`)
- Modify: `ios/LifelineUITests/UITestHelpers.swift`
- Test: create `ios/LifelineUITests/PeopleUITests.swift`

**Interfaces:**
- Consumes: Task 1 `EntityRepository.summaries(type:)`, `EntitySummary`.
- Produces:
  - `UITestSeed.writePeople(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository) throws`, under the launch argument `-uiTesting-seedPeople`. It saves a profile, so first open is done and a test must not call `skipFirstOpen()`. It writes, all invented:
    - Profile: `displayName: "Jordan"`, birth date 1 June 1990. Jordan becomes the owner entity.
    - People: Maya, Dad, Sam, Lena. Place: Alder Street.
    - Moments (kind `event`, range `.year(y, origin: .stated, evidence: "in \(y)")`, relation `mention`): "The tree house" 1999 (Maya "my sister", Dad "my dad", Alder Street, Jordan); "Learning to swim" 2000 (Maya "my sister", Dad "my dad", Alder Street, Jordan); "The science fair" 2001 (Maya, Dad "my dad"); "Maya's graduation" 2003 (Maya); "Moving into Hemenway Street" 2012 (Sam "my roommate").
    - Details (kind `fact`, relation `detail`): Maya "um, two years younger than me, you know"; Maya "she was always the the brave one"; Sam "we shared that terrible futon for most of 2012".
    - Lena has no link.
  - `EntitiesViewModel.rows: [EntitySummary]`; `EntitiesViewModel.init` does no reads. `refresh()` reads `summaries(type:)`, the owner and the tags: a fixed number of queries.
  - `EntityRows(rows: [EntitySummary], deps: Dependencies, onChange: @escaping () -> Void)`. The row text is `EntityPage.spanText(row.span)`.
  - `EntityViewModel.init` does no reads. `private(set) var isLoaded = false` becomes true after the first `refresh()`. `EntityScreen` already refreshes in `onAppear`.
  - In `UITestHelpers.swift`, on `XCUIApplication`:
    - `static func launchWithPeople(_ extra: [String] = []) -> XCUIApplication`: launches with `-uiTesting -uiTesting-seedPeople` plus `extra`, and waits until `home.start` is hittable. It does not call `skipFirstOpen()`.
    - `func entityRowLabels() -> [String]`: the `entities.row` labels, top to bottom, then leading to trailing.
    - `func openEntityPage(_ title: String)`: opens People, taps the `entities.row` with that label, and waits for `entity.title`.

- [ ] **Step 1: Add the seed and commit it alone.** The seed commit touches only `UITestSeed.swift` and `Dependencies.swift`. It uses only APIs that exist at `63c0463`, so Task 8 can cherry-pick it onto the base for the "before" screenshots.

```bash
git add ios/Lifeline/UITestSeed.swift ios/Lifeline/Dependencies.swift
git commit -m "UI tests: an invented family to seed People and their pages"
```

- [ ] **Step 1b: Add the three helpers to `UITestHelpers.swift`.** They go into the Step 6 commit.

- [ ] **Step 2: Write the failing UI test**

```swift
final class PeopleUITests: XCTestCase {
    @MainActor
    func testTheSeedReachesEveryList() {
        let app = XCUIApplication.launchWithPeople()
        app.openTab("People")
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(Set(app.entityRowLabels()), ["Maya", "Dad", "Sam", "Lena"], "the owner, Jordan, is never a row")
        app.openTab("Places")
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Alder Street")).firstMatch.waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 3: Run `-only-testing:LifelineUITests/PeopleUITests`.** Expected: PASS at once, because the seed is in. This test guards the refactor in Step 4.
- [ ] **Step 4: Change the two view models and `EntityRows` as the Interfaces block says.** Remove `Row` and its per-row `span(of:)` and `links(to:)` calls.
- [ ] **Step 5: Run `swift test`, then `-only-testing:LifelineUITests/PeopleUITests -only-testing:LifelineUITests/EntitiesUITests -only-testing:LifelineUITests/ShellUITests`.** Expected: PASS.
- [ ] **Step 6: Commit** — `Lists read their rows in batches; pages read only when shown` (with `PeopleUITests.swift` and `UITestHelpers.swift`)

### Task 5: App — the entity page

**Files:**
- Create: `ios/Lifeline/Screens/Entities/LifeStripView.swift`, `ios/Lifeline/Screens/Entities/OftenWithSection.swift`
- Modify: `ios/Lifeline/Screens/Entities/EntityScreen.swift`, `ios/Lifeline/Screens/Entities/EntityViewModel.swift`
- Test: create `ios/LifelineUITests/EntityPageUITests.swift`; modify `ios/LifelineUITests/EntitiesUITests.swift:44` and `:58` (copy only)

**Interfaces:**
- Consumes: Task 1 `coOccurrences(of:)`, `ownWords(of:)`; Task 2 `LifeStrip`; Task 3 `EntityPage.sections`, the three copy functions, `ReadableQuote.text`; Task 4 `isLoaded`, `XCUIApplication.launchWithPeople`, `openEntityPage(_:)`.
- Produces:
  - `EntityViewModel`: `ownWords: String?`, `strip: LifeStrip?` (nil for an idea), `said: [Memory]`, `moments: [Memory]`, `oftenWith: [CoOccurrence]`, `statedSpanText: String?` (`EntityPage.spanText(entity.range)` only when `entity.range.isPlaced`). `details`, `coOccurring` and `spanText` go. `ideaLines` stays.
  - `LifeStripView(strip: LifeStrip)`: one accessibility element whose label is `strip.sentence`. With `strip.showsAxis`, it draws the axis, the marks (a guess is hollow), the stated span bar and the labels "{startYear}" and "now"; identifier `entity.strip`. Without the axis it shows the sentence only; identifier `entity.stripSentence`. The axis height is a `@ScaledMetric` with base 16 points.
  - `OftenWithSection(items: [CoOccurrence])`: header "Often with"; a `FlowLayout` of chips. Each chip is a `NavigationLink` to that entity's page, with identifier `entity.oftenWith` and label "{title}, {n} moments together". It shows the title and the count, and is at least 44 points high.
- Page order for a person, place or thing (spec "Entity page"): the type caption, the title, the own words (`entity.ownWords`), the stated span (`entity.span`), Play; the strip; the said section (`EntityPage.saidHeading`, rows `entity.detail` with the full `ReadableQuote.text`, label the same text); "Often with"; the moments section (`EntityPage.momentsHeading`, rows `entity.moment`, the date in `Theme.ochreText` above the title, label the title); the invitation (`entity.invite`) only when `isLoaded` and `said` and `moments` are both empty; Tags.
- Each section shows only when it has content. "Nothing said about it yet." and "No moments yet." go.
- The "Add a tag" button and the tag buttons: `.buttonStyle(.bordered)`, `.buttonBorderShape(.capsule)`, `.controlSize(.small)`, `.tint(Theme.oliveText)` (the tag buttons keep `Theme.secondaryText`), `.fixedSize()`, a 44-point hit area. Find the cause of the tall grey pill first (Step 3); the fix must address that cause.

- [ ] **Step 1: Write the failing UI tests**

```swift
final class EntityPageUITests: XCTestCase {

    @MainActor
    func testAPersonsPageReadsInTheSpecOrder() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Maya")
        XCTAssertEqual(app.any("entity.ownWords").label, "my sister")
        XCTAssertEqual(app.any("entity.strip").label, "In 4 moments, from 1999 to 2003")
        XCTAssertTrue(app.staticTexts["What you've said about them"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "entity.detail").allElementsBoundByIndex.map(\.label),
                       ["Two years younger than me", "She was always the brave one"])
        XCTAssertEqual(app.buttons.matching(identifier: "entity.oftenWith").allElementsBoundByIndex.map(\.label),
                       ["Dad, 3 moments together", "Alder Street, 2 moments together"])
        let moments = app.buttons.matching(identifier: "entity.moment")
        XCTAssertTrue(app.reveal(app.staticTexts["Moments with Maya"]))
        XCTAssertEqual(moments.count, 4)
        XCTAssertLessThan(app.any("entity.strip").frame.minY, app.buttons["entity.detail"].firstMatch.frame.minY)
        XCTAssertLessThan(app.buttons["entity.detail"].firstMatch.frame.minY, app.buttons["entity.oftenWith"].firstMatch.frame.minY)
        XCTAssertLessThan(app.buttons["entity.oftenWith"].firstMatch.frame.minY, moments.firstMatch.frame.minY)
        XCTAssertFalse(app.staticTexts["Jordan"].exists, "the owner is never often with anyone")
    }
    @MainActor
    func testOftenWithOpensThatPage() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Maya")
        app.buttons.matching(identifier: "entity.oftenWith").firstMatch.tap()
        let title = app.staticTexts["entity.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.label, "Dad")
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story about Dad")
    }
    @MainActor
    func testAPageWithOneMomentHasNoAxis() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Sam")
        XCTAssertEqual(app.any("entity.stripSentence").label, "In one moment, in 2012")
        XCTAssertFalse(app.any("entity.strip").exists)
        XCTAssertFalse(app.staticTexts["Often with"].exists, "absent, not empty")
    }
    @MainActor
    func testAPageWithNothingInvitesAStory() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Lena")
        XCTAssertEqual(app.any("entity.invite").label, "Stories you tell about Lena will show here.")
        for absent in ["What you've said about them", "Often with", "Moments with Lena"] { XCTAssertFalse(app.staticTexts[absent].exists) }
        XCTAssertFalse(app.any("entity.strip").exists || app.any("entity.stripSentence").exists)
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story about Lena")
    }
    @MainActor
    func testAddATagIsASmallPill() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Lena")
        let add = app.buttons["entity.addTag"]
        XCTAssertTrue(app.reveal(add))
        XCTAssertLessThanOrEqual(add.frame.height, 48)
        XCTAssertGreaterThan(add.frame.width, add.frame.height)
    }
}
```

`EntitiesUITests` changes copy only, with equal strength. Line 44: `XCTAssertTrue(app.staticTexts["no dates yet"].exists, "nobody asks when")` becomes `XCTAssertEqual(app.any("entity.stripSentence").label, "In one moment", "nobody asks when")`. Line 58: `XCTAssertEqual(app.staticTexts["entity.span"].label, "in 1995")` becomes `XCTAssertEqual(app.any("entity.stripSentence").label, "In one moment, in 1995")`. The detail label "The house had a blue door" stays: `ReadableQuote` capitalises the quote "the house had a blue door".

- [ ] **Step 2: Run `-only-testing:LifelineUITests/EntityPageUITests -only-testing:LifelineUITests/EntitiesUITests`.** Expected: FAIL, the new identifiers do not exist.
- [ ] **Step 3: Take a simulator screenshot of a page's Tags section before the change. Find why "Add a tag" draws as a tall grey pill.** Write the cause in one line in the commit body.
- [ ] **Step 4: Build the page as the Interfaces block says.** `EntityViewModel.refresh()` reads: the entity, the owner, `details(of:)`, `moments(of:)`, `coOccurrences(of:)`, `ownWords(of:)`, the birth date, the tags and the first telling. It builds `strip` with `LifeStrip(moments: sections.moments.map(\.range), stated: entity.range, birthYear: birth?.year, currentYear: CivilDate.today().year)`. An idea keeps its "Over time" section and gets `OftenWithSection` in place of "Beside it".
- [ ] **Step 5: Run `swift test`, then `-only-testing:LifelineUITests/EntityPageUITests -only-testing:LifelineUITests/EntitiesUITests -only-testing:LifelineUITests/ShellUITests`.** Expected: PASS.
- [ ] **Step 6: Commit** — `Entity page: life strip, what you've said, often with, moments in order`

### Task 6: App — the People grid

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/PeopleGrid.swift` (`PeopleSort`, `Monogram`), `ios/LifelineKit/Tests/LifelineKitTests/PeopleGridTests.swift`
- Modify: `ios/LifelineKit/Sources/LifelineKit/Support/Palette.swift`, `ios/LifelineKit/Tests/LifelineKitTests/PaletteTests.swift`, `ios/Lifeline/Support/Theme.swift`
- Create: `ios/Lifeline/Screens/Entities/PeopleGridScreen.swift`, `ios/Lifeline/Screens/Entities/PersonTile.swift`
- Modify: `ios/Lifeline/Screens/Shell/SectionsScreen.swift` (`PeopleTabRoot` shows `PeopleGridScreen`)
- Test: `ios/LifelineUITests/PeopleUITests.swift`

**Interfaces:**
- Consumes: Task 1 `EntitySummary`; Task 4 `EntitiesViewModel.rows`, `XCUIApplication.launchWithPeople`, `entityRowLabels()`, `openEntityPage(_:)`.
- Produces:
  - `public enum PeopleSort: String, CaseIterable, Sendable { case mostTold, firstInStory, byName }` with `public var title: String` and `public func sorted(_ people: [EntitySummary]) -> [EntitySummary]` (decision 9; ties by title, ignoring case).
  - `public enum Monogram { public static func letter(for title: String) -> String; public static func tintIndex(for id: EntityID) -> Int }`. `letter` is the first letter, upper-cased; with no letter, the first character.
  - `Palette.monogramTints: [Int] = [0xE3DCC6, 0xDDE2D3, 0xEADBCB]`; `Theme.monogramTints: [Color]`.
  - `PeopleGridScreen(deps: Dependencies)`: an `EntitiesViewModel` of type `.person`, so the tag filter (`entities.tagFilter`) works as before. The navigation title is "People". The toolbar has a sort `Menu` (identifier `people.sort`; its label is the current sort's title; items `people.sort.mostTold`, `people.sort.firstInStory`, `people.sort.byName`). `@State var sort: PeopleSort = .mostTold`. A `LazyVGrid` with identifier `people.grid` (decision 12), or a `List` with identifier `people.list` at accessibility size 3 and larger. The empty state is unchanged.
  - `PersonTile(summary: EntitySummary)`: a `NavigationLink` to the page. The face is a rounded square (`aspectRatio(1)`, corner radius 22) that holds `TileFace`. `TileFace` draws the letter in the serif face on `Theme.monogramTints[Monogram.tintIndex(for:)]`. S4 replaces `TileFace`'s content with the photo and keeps the frame. Under the face: the title (serif headline) and the own words (`Theme.secondaryText`, footnote), or an empty line. Identifier `entities.row`. Accessibility label: the title. Accessibility value: the own words. No count and no date on the tile.

- [ ] **Step 1: Write the failing tests**

```swift
// PeopleGridTests
@Test func theSortsOrderPeopleAsNamed() {
    // maya: 4 moments, first 1999; dad: 3, first 1999; sam: 1, first 2012; lena: 0, none
    #expect(PeopleSort.mostTold.sorted(all).map(\.entity.title) == ["Maya", "Dad", "Sam", "Lena"])
    #expect(PeopleSort.firstInStory.sorted(all).map(\.entity.title) == ["Dad", "Maya", "Sam", "Lena"])
    #expect(PeopleSort.byName.sorted(all).map(\.entity.title) == ["Dad", "Lena", "Maya", "Sam"])
    #expect(PeopleSort.allCases.map(\.title) == ["Most told", "First in your story", "By name"])
}
@Test func theMonogramIsTheFirstLetter() {
    #expect(Monogram.letter(for: "maya") == "M")
    #expect(Monogram.letter(for: "Mr. Alvarez") == "M")
    #expect(Monogram.letter(for: "“Bird”") == "B")
    #expect(Monogram.letter(for: "Élodie") == "É")
    #expect(Monogram.letter(for: "42") == "4")
}
@Test func theTintIsFixedByTheID() {
    #expect(Monogram.tintIndex(for: EntityID(rawValue: "00000000-0000-0000-0000-000000000000")) == 0)
    #expect(Monogram.tintIndex(for: EntityID(rawValue: "A")) == 2)
    let id = EntityID()
    #expect(Monogram.tintIndex(for: id) == Monogram.tintIndex(for: EntityID(rawValue: id.rawValue)))
}
// PaletteTests
@Test func inkPassesOnEveryTint() {
    for tint in Palette.monogramTints { #expect(Palette.contrast(Palette.ink, tint) >= 4.5) }
}
```

```swift
// PeopleUITests
@MainActor
func testPeopleIsAGridOfNamesAndOwnWords() {
    let app = XCUIApplication.launchWithPeople(); app.openTab("People")
    XCTAssertTrue(app.any("people.grid").waitForExistence(timeout: 5))
    XCTAssertEqual(app.entityRowLabels(), ["Maya", "Dad", "Sam", "Lena"])
    let tiles = app.buttons.matching(identifier: "entities.row").allElementsBoundByIndex
        .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    XCTAssertEqual(tiles.map { $0.value as? String ?? "" }, ["my sister", "my dad", "my roommate", ""])
    XCTAssertEqual(tiles[0].frame.minY, tiles[2].frame.minY, accuracy: 1, "three to a row")
    XCTAssertEqual(app.buttons["people.sort"].label, "Most told")
}
@MainActor
func testTheSortMenuReorders() {
    let app = XCUIApplication.launchWithPeople(); app.openTab("People")
    app.buttons["people.sort"].tap(); app.buttons["people.sort.byName"].tap()
    XCTAssertEqual(app.entityRowLabels(), ["Dad", "Lena", "Maya", "Sam"])
    app.buttons["people.sort"].tap(); app.buttons["people.sort.firstInStory"].tap()
    XCTAssertEqual(app.entityRowLabels(), ["Dad", "Maya", "Sam", "Lena"])
    XCTAssertEqual(app.buttons["people.sort"].label, "First in your story")
}
@MainActor
func testATileOpensItsPage() {
    let app = XCUIApplication.launchWithPeople(); app.openTab("People")
    app.openEntityPage("Maya")
    XCTAssertEqual(app.staticTexts["entity.title"].label, "Maya")
}
@MainActor
func testNoTileOffersAPhoto() {
    let app = XCUIApplication.launchWithPeople(); app.openTab("People")
    XCTAssertTrue(app.any("people.grid").waitForExistence(timeout: 5))
    XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).count, 0)
}
@MainActor
func testTheGridBecomesAListAtTheLargestTextSize() {
    let app = XCUIApplication.launchWithPeople(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    app.openTab("People")
    XCTAssertTrue(app.any("people.list").waitForExistence(timeout: 5))
    XCTAssertFalse(app.any("people.grid").exists)
    XCTAssertEqual(Set(app.entityRowLabels()), ["Maya", "Dad", "Sam", "Lena"])
}
```

- [ ] **Step 2: Run `swift test --filter "PeopleGrid|Palette"` and `-only-testing:LifelineUITests/PeopleUITests`.** Expected: FAIL.
- [ ] **Step 3: Implement the kit types, the tints, `PeopleGridScreen` and `PersonTile`; show the grid in `PeopleTabRoot`.** Keep the `people.more` menu with "Names you mentioned" (`home.people`). Run `xcodegen generate` after adding the files.
- [ ] **Step 4: Run `swift test`, then `-only-testing:LifelineUITests/PeopleUITests -only-testing:LifelineUITests/ShellUITests -only-testing:LifelineUITests/EntitiesUITests`.** Expected: PASS. `ShellUITests.openMaya` still finds the one `entities.row` labelled "Maya".
- [ ] **Step 5: Commit** — `People: a grid of names and your words for them, sorted three ways`

### Task 7: App — readable quotes on About, and olive text on bordered buttons

**Files:**
- Modify: `ios/Lifeline/Screens/Timeline/AboutSection.swift:17`
- Modify the olive tint where it colours text: `ios/Lifeline/Screens/Cards/PairCard.swift:39`, `ios/Lifeline/Screens/Cards/MemoryCard.swift:82,87,167`, `ios/Lifeline/Screens/Landing/LandingScreen.swift:126`, `ios/Lifeline/Screens/Cards/WhoIsThisCard.swift:27`, `ios/Lifeline/Screens/Cards/DisclosureCard.swift:25`, `ios/Lifeline/Screens/Cards/ChangeSheet.swift` (each `.bordered` button tinted `Theme.olive`), `ios/Lifeline/Screens/Memory/MemoryScreen.swift:70` (the "Play" label)

**Interfaces:**
- Consumes: Task 3 `ReadableQuote.text(_:maxWords:)`.
- Produces: nothing new.

- [ ] **Step 1: Run the check that finds the defect.**

Run: `git grep -n -A1 "buttonStyle(.bordered)" ios/Lifeline | grep "Theme.olive)"`
Expected now: lines in the files above. Expected after Step 2: no output.

- [ ] **Step 2: Change the tint to `Theme.oliveText` on every bordered button and on the "Play" label in `MemoryScreen`.** `.borderedProminent` buttons keep `Theme.olive`: white text on olive passes 4.5:1. Icon-only buttons (the `PairCard` play icon) keep `Theme.olive`.
- [ ] **Step 3: In `AboutSection`, show `ReadableQuote.text(row.memory.summaryQuote, maxWords: 40)` and remove `.lineLimit(3)`.** The row's accessibility label stays the title. The memory page keeps the raw quote (audit, owner's call 1).
- [ ] **Step 4: Run the Step 1 check, `swift test`, then `-only-testing:LifelineUITests/KindsUITests -only-testing:LifelineUITests/SameStoryUITests -only-testing:LifelineUITests/LandingUITests`.** Expected: no output from the check; PASS.
- [ ] **Step 5: Commit** — `Readable quotes under About; olive text on bordered buttons`

### Task 8: Docs, screenshots, the device check, the whole suite

**Files:**
- Modify: `docs/OVERVIEW.md` (the "shape of the app" paragraph, "Not everything is a moment", section 6 "Kinds and entities")
- Create: `docs/plans/2026-11-15-sections-pages-device-check.md`
- Create: `docs/screenshots/sections-pages/before-people.png`, `before-maya.png`, `before-lena.png`, `after-people.png`, `after-maya.png`, `after-sam.png`, `after-lena.png`, `after-people-largest-text.png`

- [ ] **Step 1: Take the "before" screenshots.** Create a temporary worktree at the base: `git worktree add ../lifeline-pages-before 63c0463`. Cherry-pick the seed commit from Task 4 Step 1. In both worktrees, add an uncommitted UI test file `ScreenshotTour.swift`. It launches with `-uiTesting -uiTesting-seedPeople`, opens People, Maya, Lena (and, after, Sam and the largest text size), and adds each screen as a kept `XCTAttachment`. Run it with `-resultBundlePath`. Export with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`. Copy the images to `docs/screenshots/sections-pages/` under the names above. Then remove the temporary worktree and delete `ScreenshotTour.swift`. Never copy `Local.xcconfig` into a commit.
- [ ] **Step 2: Update OVERVIEW.** Describe the People grid and its three sorts, the page's order, the strip and its sentence, "Often with", and that quotes on lists and pages hide filler words while the memory page and the audio keep every word.
- [ ] **Step 3: Write the device checklist.** Each item is one line the owner ticks on the iPhone:
  1. People shows a grid in light and dark appearance. Each letter tile keeps its tint after a relaunch.
  2. At the largest accessibility text size, People is a list and every name reads in full.
  3. VoiceOver reads a tile as the name and the person's words, and reads the strip as one sentence.
  4. On a page with a strip, the marks match the sentence. A guessed date reads "around" or "between".
  5. "Often with" opens the other page, and the record bar names that page.
  6. A page with nothing told shows only the invitation and Tags. "Add a tag" is a small pill.
  7. On the owner's real archive, no page shows the owner in "Often with", and no quote starts mid-word.
  8. Open People and three pages in a row; nothing stalls.
- [ ] **Step 4: Run `swift test`, then the whole UI suite once:** `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE'`. Expected: PASS, every test. If a test fails, fix the cause and run the whole suite again.
- [ ] **Step 5: Check that `git status` shows no `ios/Config/Local.xcconfig` and no `ScreenshotTour.swift`.**
- [ ] **Step 6: Commit** — `Docs: pages and People in the overview, screenshots, and the device checklist`

---

## After S2

The umbrella plan's rule stands: watch two weeks of the owner's use before S6 to S9 are planned in detail. S3 (You), S4 (photos) and S5 (search) may start in any order. S3 takes decision 17 (facts about others leave About). S4 replaces `TileFace`'s content with the photo.
