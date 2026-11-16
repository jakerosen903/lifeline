# S3: You as a Portrait Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The You tab becomes a portrait of the person in their own words and voice: their name and birth line, their life strip, one line of theirs in large type, then "Who you are", "How it felt", "What you think" and "What you're hoping for". Every line can play the part of the recording where they said it. The flat "About" list leaves Timeline.

**Architecture:** Task 1 adds batched reads to the kit, so the whole portrait loads in a fixed number of queries. Task 2 adds a pure `Portrait` type in `Domain/` that decides which line goes in which part, which line leads, and the copy. Tasks 3 and 4 build the screen and its play controls in the app. Task 5 removes About from Timeline and gives hide and delete a home on You. Task 6 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, GRDB 7 (no migration), AVFoundation through the existing `SegmentPlayer`, Swift Testing, XCUITest.

**Spec:** `docs/specs/2026-11-15-five-sections.md`, sections "You", "The life strip", "Data", "Appearance and accessibility", "Owner's calls" (call 2: names by age only) and "Left to the builder". The UI audit `docs/specs/2026-10-26-ui-audit.md`, findings F9 ("About" holds 62% of everything) and F10 (the owner is a person entity), and its rule "About keeps only what is about the owner. Group it by domain tag." The umbrella plan `docs/plans/2026-11-15-sections.md`, Part 1 (S3 builds on S2; photos are S4, search S5, Timeline S6, Things S7, Places S8, guessed locations S9). The S2 plan `docs/plans/2026-11-15-sections-pages.md`, decision 17 and "After S2". Mock-ups: `docs/design/Sections.html`, the screens "You, at the top" and "You, further down". Read all of these before Task 1.

**Worktree and branch:** `/Users/jakerosen/dev/lifeline/lifeline-you`, branch `sections-you`, based on the tip of `origin/sections-pages` (`4609a3c`). Work only there.

---

## Decisions made in this plan

The spec leaves these open. Each one is decided here so the owner can overrule it before work starts.

1. **No migration.** Every S3 need comes from `memory`, `memory_span`, `segment`, `session`, `moment_entity`, `entity`, `entity_span`, `domain_tag`, `person` and `profile`. v12 stays the last migration. If a change in S3 needs a migration after all, its number is confirmed at implementation time, because another branch may take v13.
2. **"Who you are" (S2 decision 17).** A fact shows under "Who you are" when it has a `detail` link to the owner, or no `detail` link at all. A fact with a `detail` link only to someone or something else shows on that page (S2 already does this) and not on You. A `mention` link does not move a fact. Hidden facts and floating stand-ins never show.
3. **"How it felt" and "What you're hoping for"** hold every shown feeling and every shown goal, whoever they are about. They are the person's own feelings and hopes.
4. **What a feeling is about.** The first non-owner person, place or thing linked by `detail`, else the first one linked by `mention`, by title. The line under the feeling reads "about {title}" and opens that page. With no such link, no line shows. The app does not guess one (non-negotiable 3).
5. **No dates on facts and feelings.** The mock-up shows "about 2014" under a feeling. M7 decided that a non-moment shows no date, and a feeling's stored range is often inferred. The feeling shows only its "about" line. A goal shows when it was said: "said in October" in the current year, "said in October 2025" before it. That is when the session started, which the app knows; it is not a guess.
6. **Line text.** A fact, a feeling or a goal shows `EntityPage.ownWordsQuote(of:)` in quotation marks, with no word limit. When the cleanup leaves nothing, it shows the memory's title with no quotation marks (`EntityPage.readableQuote(of:)`). An idea shows its title, large and plain, as in the mock-up. An idea's title is the person's own words or the dated default "An idea you mentioned on …"; neither is drawn as a quote.
7. **Order inside a part.** Facts, feelings and goals: oldest told first. Ideas: by title, as `EntityRepository.entities(type: .idea)` returns them.
8. **The lead line.** It is chosen from the shown facts, feelings and goals that have own words and a recording. It is chosen again each time the You root appears (on tab selection and on return from a pushed page). A refresh after a session closes or after Settings keeps the same lead while it is still in the pool. The lead does not repeat in its part. A part that then has nothing does not show. With an empty pool, no lead shows.
9. **A deterministic lead under test.** `Dependencies.pickLead: @Sendable (Int) -> Int` returns `Int.random(in: 0..<count)` in the app and `0` under `-uiTesting`.
10. **The lead's control** reads "Hear yourself say it, {m:ss}" (mock-up copy), the length of the span, through `Format.duration(ms:)`. While it plays it reads "Stop". A line's own control is a 44-point play symbol with the accessibility label "Hear yourself say it", or "Stop" while it plays. One line plays at a time.
11. **What a line plays.** A memory plays its first telling (the span with the lowest `order`). An idea plays its first `entity_span`. A line with no span shows no control. The play control plays only that span; the memory page keeps play-through of continued tellings.
12. **Domain chips.** They show above "Who you are" when at least one listed fact has a tag: "All", then each tag on the listed facts, once each, ignoring case, sorted ignoring case. The filter starts on "All" at each launch and is not remembered. When the chosen tag is no longer on any listed fact, the filter goes back to "All". The selected chip is filled and carries the `.isSelected` trait and a checkmark, so selection is not told by colour alone.
13. **The header.** The owner's name (`Profile.displayName`, else the owner entity's title) in the serif title face. Under it, the birth line: "born 1990 in Dayton", "born 1990", "born in Dayton", or nothing. The place is `Profile.birthPlaceText`, which the person typed. With no name, no name line shows.
14. **The life strip on You** is the owner's strip: `LifeStrip` over the owner's moments (S2 decision 2), from the birth year to now. It is the way to the owner's own page: the strip is a `NavigationLink` with the identifier `entities.aboutYou`, and its label is the strip's sentence. With no moments linked to the owner, no strip and no link show. The "About you" row goes. Photos on the strip wait for S4.
15. **A You page with nothing to show** shows the header and one line: "Stories you tell about yourself will show here." (`EntityPage.invitation(title:isOwner: true)`). The record bar already reads "Tell a story about yourself". There is no other prompt, field or count.
16. **Ideas keep their home on You** under "What you think". Each idea row keeps the identifier `entities.row` and its title as its label, and opens the idea's page, which keeps "Over time" and "Often with".
17. **Hide and delete** move from the About row menu to a context menu on each fact, feeling and goal line: "Hide" and "Delete…". "Delete…" asks first, with the Timeline's copy. The word "timeline" leaves the hide label, because the line is not on Timeline. Ideas keep their own page's menu.
18. **Timeline after About.** The About section and `AboutSection.swift` go. The summary line keeps "and N things about your life", so a person who told only facts does not see the "Your story so far" empty state. The empty state still counts non-moments.
19. **Layout.** The portrait is a `ScrollView` with a plain `VStack`, not a `List` and not a lazy stack. A portrait has tens of lines, and every line exists for VoiceOver and for UI tests without scrolling.
20. **No life periods on You.** The spec groups Timeline, Things and Places by life period, not You. S3 names no period, so owner's call 2 (names by age only, only with a birth date) is not touched.

### Conflicts and limits found while planning

- **Facts about other people with no link (owner should know).** Decision 2 trusts the extractor's `detail` link. The audit counted 3 detail links in 37 memories, so on the owner's archive most facts about other people have no link and stay under "Who you are" until extractor v7 re-reads the archive (track A, with the owner-is-self rule). This is the smallest honest version: the app does not guess who a fact is about. When v7 runs, the facts move to their pages with no change to S3.
- **Unhiding a fact.** Today a hidden fact, feeling or goal cannot be shown again: the About menu only hides, and the memory page has no hide control. S3 keeps that as it is and does not add a "show hidden" control to You. A way back is a follow-up for the owner to place.
- **Out of S3's scope, by the ship order:** photos on the strip and "Add a photo" on You (S4); search (S5); the strip at the top of Timeline and life periods (S6).
- **Dark and increased-contrast values** still have no PR. S3 uses only `Theme` tokens and system materials, so a later palette change reaches every new view.

---

## Global Constraints

- Deployment target iOS 26.0. Swift 6 with complete strict concurrency.
- No migration in this PR (decision 1). Never edit a shipped migration.
- Copy, exact:
  - Part headings: "Who you are", "How it felt", "What you think", "What you're hoping for".
  - Chips: "All", then the person's own tags.
  - Lead control: "Hear yourself say it, {m:ss}"; while playing: "Stop". A line's control, accessibility label: "Hear yourself say it"; while playing: "Stop".
  - Feeling: "about {title}". Goal: "said in {Month}" or "said in {Month} {year}".
  - Birth line: "born {year} in {place}", "born {year}", "born in {place}".
  - Invitation: "Stories you tell about yourself will show here."
  - Context menu: "Hide", "Delete…". Delete dialog: title "Delete this memory?", button "Delete “{title}”", message "The memory, its people and its dates go. Your recording stays in Sessions."
  - Play error: "Could not play this: {reason}".
  - Toolbar: "Settings" (identifier `home.settings`). Record bar on You: "Tell a story about yourself" (unchanged).
- Quotation marks go only around the person's own words (`EntityPage.ownWordsQuote`). A title is never drawn as a quote. Stored text and audio never change (PRINCIPLES 1, audit owner's call 1).
- Nothing inferred reads as fact: no guessed "about" link, no date on a fact or a feeling, no life-period name (PRINCIPLES 5, non-negotiable 3).
- No screen asks the person to complete a record: no empty field, no "add" prompt, no count of what is missing, no empty part (PRINCIPLES 9).
- You reads in a fixed number of queries, never one per line. `YouViewModel.init` does no reads. The screen reads in `onAppear` and, while visible, when `home.coverClosings` changes.
- Text colours: `Theme.ink`, `Theme.secondaryText`, `Theme.oliveText`, `Theme.ochreText`. `Theme.oliveOnFill` tints bordered buttons. `Theme.olive` is for fills and prominent buttons only. `Theme.hairline` is for rules only. Headings use `sectionHeadingStyle()`. Every text colour reaches 4.5:1 on its surface. No new colour values (dark and increased-contrast values are not in this PR).
- Every control is at least 44 by 44 points, with the frame inside the button's label. Metadata uses the footnote style or larger. No `lineLimit` on a line of the person's words; Dynamic Type must not clip.
- Keep these accessibility identifiers: `home.settings`, `home.start`, `entities.aboutYou`, `entities.row`, `entity.title`, `memory.kind`, `memory.change`, `timeline.summary`, `timeline.showHidden`, `row.confirmDelete`. New ones: `you.name`, `you.birth`, `you.lead`, `you.lead.play`, `you.tag.all`, `you.tag`, `you.line`, `you.play`, `you.feelingAbout`, `you.invite`, `you.error`, `you.hide`, `you.delete`. Removed: `timeline.about`, `about.row`, `about.more`.
- Kit tests: `cd ios/LifelineKit && swift test`. They run in full at every task.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`. Each task names the classes it runs. The task report gives the verbatim `Executed N tests, with M failures` line for each class. The whole UI suite runs once, by the controller, after the final review's fixes. No task runs it.
- Real TDD: each new test is seen failing before the code that makes it pass.
- No test's assertions are weakened. A test that asserts behaviour this plan changes moves to the new behaviour with an assertion of equal strength. The plan names each one: `KindsUITests.testFactKeptLandsUnderAbout`, renamed `testAFactAboutTheHouseLandsOnItsPage` (Task 5); `ShellUITests.testTheYouTabIsAboutYourself` (Task 3). Playback with a real file is not reachable under UI tests (the seeds write no audio); device checklist item 3 covers it.
- `ios/Config/Local.xcconfig` is never committed.
- Commit messages are imperative and one line, with a body when the why is not obvious. No AI attribution lines. Nothing is pushed.
- Fixtures are invented. Never a real person's words.
- Before and after simulator screenshots with invented data go under `docs/screenshots/sections-you/` (Task 6).
- Docs under `docs/` use ASD-STE100 style.

## Review Focus

1. **The recording is missing** (a session's audio file is gone, or a seed never wrote one): tapping play shows "Could not play this: …" and the page stays as it was. Task 4 (`testAMissingRecordingSaysSoAndKeepsThePage`; the seed's `seed.m4a` does not exist).
2. **A quote that is only filler** ("um, uh"): the line shows its title without quotation marks and never leads. Task 2 (`aQuoteOfOnlyFillerShowsTheTitleAndNeverLeads`) and Task 3 (`testThePortraitReadsInTheSpecOrder`, the line "Something about Ohio").
3. **A page with one line**: the line leads, its part does not show as an empty heading, and the pick is never out of range; with no line, no lead and no pick. Task 2 (`oneLineLeadsAndItsPartHides`, `anEmptyPoolPicksNothing`).
4. **The chosen chip's tag is removed** (on the memory page, or the last fact with it is hidden): the filter goes back to "All", never to an empty part. Task 2 (`aTagThatIsGoneShowsEverything`).
5. **The largest accessibility text size**: the lead, the chips and every line read in full, and each play control keeps 44 points. Task 3 (`testTheLargestTextSizeKeepsEveryLine`) and Task 4 (`testEveryPlayControlIsFullSize`).

---

### Task 1: Kit — batched reads for the portrait

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/Telling.swift` (`Telling`, `AboutLink`)
- Create: `ios/LifelineKit/Sources/LifelineKit/Store/PortraitReads.swift` (`PortraitSource`, `ExtractionStore.portraitSource()`)
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/MemoryRepository.swift` (add `firstTellings(kinds:)` under `// MARK: - Spans`)
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/EntityRepository.swift` (add `firstTellings(type:)` and `aboutLinks(kinds:)` to `// MARK: - Batched reads`)
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/DomainTagRepository.swift` (add `tagsByElement(_:)`)
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/PortraitReadsTests.swift`

**Interfaces:**
- Consumes: `MemoryRepository.aboutMemories(includingHidden:)`, `EntityRepository.moments(of:)`, `entities(type:)`, `ProfileRepository.fetch()`, `owner()`, `ownerBirthDate()`, `MsRange`, the `StatementCounter` pattern in `EntityBatchReadsTests.swift`.
- Produces:
  - `public struct Telling: Sendable, Equatable { public var sessionID: SessionID; public var audioPath: String; public var range: MsRange; public var toldAt: Date }`. `toldAt` is the session's `started_at`.
  - `public struct AboutLink: Sendable, Equatable { public var entity: Entity; public var relation: EntityRelation }`
  - `MemoryRepository.firstTellings(kinds: Set<MemoryKind>) throws -> [MemoryID: Telling]`: one query over `memory_span` (lowest `order` per memory) joined to `segment` and `session`, for memories of those kinds.
  - `EntityRepository.firstTellings(type: EntityType) throws -> [EntityID: Telling]`: one query over `entity_span` (lowest `order` per entity) joined to `segment` and `session`.
  - `EntityRepository.aboutLinks(kinds: Set<MemoryKind>) throws -> [MemoryID: [AboutLink]]`: one query over `moment_entity` joined to `entity` and `memory`. Hidden entities are included (decision 2 needs them). Each list is ordered `detail` before `mention`, then by title ignoring case.
  - `DomainTagRepository.tagsByElement(_ kind: ElementKind) throws -> [String: [String]]`: one query; each list ordered ignoring case.
  - `public struct PortraitSource: Sendable { public var profile: Profile?; public var owner: Entity?; public var birth: CivilDate?; public var ownerMoments: [Memory]; public var aboutMemories: [Memory]; public var links: [MemoryID: [AboutLink]]; public var memoryTags: [String: [String]]; public var memoryTellings: [MemoryID: Telling]; public var ideas: [Entity]; public var ideaTellings: [EntityID: Telling] }`
  - `ExtractionStore.portraitSource() throws -> PortraitSource`. It reads only the methods above plus the profile, the owner, the birth date and `moments(of: owner)`. `aboutMemories` is `aboutMemories(includingHidden: false)`.

- [ ] **Step 1: Write the failing tests**

Build the fixture with `ExtractionStore(try AppDatabase.inMemory())` and `StoreFixtures`, as `EntityBatchReadsTests` does. The owner is Jordan (save a `Profile` with `displayName: "Jordan"`, `birthPlaceText: "Dayton"`). Invented memories: f1 fact "I'm the oldest of two" (detail → Jordan, tagged "Family"), f2 fact "she was always the brave one" (detail → Maya), f3 fact (hidden), e1 feeling (detail → the place "The lake"), g1 goal (no link), and the idea "Saying yes to things" with one entity span.

```swift
@Test func firstTellingsReadTheLowestSpanWithItsSession() throws {
    // f1 has spans order 0 (2_000...6_000) and order 1 (9_000...12_000) in session s1, started 1 March 2026
    let tellings = try store.memories.firstTellings(kinds: [.fact, .feeling, .goal])
    #expect(tellings[f1.id] == Telling(sessionID: s1.id, audioPath: s1.audioPath, range: MsRange(start: 2_000, end: 6_000), toldAt: s1.startedAt))
    #expect(tellings[event.id] == nil, "a moment is not asked for")
}
@Test func ideaTellingsReadTheFirstEntitySpan() throws {
    #expect(try store.entities.firstTellings(type: .idea)[yes.id]?.range == MsRange(start: 0, end: 3_000))
    #expect(try store.entities.firstTellings(type: .idea)[quiet.id] == nil, "an idea with no span has no telling")
}
@Test func aboutLinksListDetailBeforeMentionAndKeepHiddenEntities() throws {
    // e1: mention → Alder Street, detail → The lake; f2: detail → Maya (Maya hidden)
    let links = try store.entities.aboutLinks(kinds: [.fact, .feeling, .goal])
    #expect(links[e1.id]?.map { "\($0.relation.rawValue) \($0.entity.title)" } == ["detail The lake", "mention Alder Street"])
    #expect(links[f2.id]?.first?.entity.hiddenFromTimeline == true)
    #expect(links[g1.id] == nil)
}
@Test func tagsByElementReadsEveryMemoryTagAtOnce() throws {
    #expect(try store.tags.tagsByElement(.memory)[f1.id.rawValue] == ["Family"])
}
@Test func thePortraitSourceLeavesOutHiddenAndFloatingMemories() throws {
    let source = try store.portraitSource()
    #expect(!source.aboutMemories.contains { $0.id == f3.id })
    #expect(source.aboutMemories.allSatisfy { !$0.isFloating && !$0.isMoment })
    #expect(source.profile?.birthPlaceText == "Dayton" && source.owner?.title == "Jordan")
}
@Test func thePortraitReadsInAFixedNumberOfStatements() throws {
    // Same counter as `summariesReadInAFixedNumberOfStatements`. Read with 3 facts, add 30 facts, 10 feelings,
    // 10 goals and 10 ideas, each with a span and a tag, read again.
    #expect(statementsForMany == statementsForFew)
}
```

- [ ] **Step 2: Run `cd ios/LifelineKit && swift test --filter PortraitReads`.** Expected: FAIL, the types and methods do not exist.
- [ ] **Step 3: Implement the two types, the four reads and `portraitSource()`.** "Lowest order per memory" is a `min("order")` group joined back, or a window function; either is one statement. `aboutLinks` filters `memory.kind in (…)` in SQL.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole kit suite.
- [ ] **Step 5: Commit** — `Kit: read the portrait's lines, links, tags and recordings in batches`

### Task 2: Kit — the portrait

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/Portrait.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/PortraitTests.swift`

**Interfaces:**
- Consumes: Task 1 `PortraitSource`, `Telling`, `AboutLink`; `EntityPage.ownWordsQuote(of:)`, `EntityPage.readableQuote(of:)`, `EntityPage.sections(details:mentions:)`, `LifeStrip`.
- Produces:

```swift
public struct PortraitLine: Sendable, Equatable, Identifiable {
    public enum Part: Sendable, Equatable { case whoYouAre, howItFelt, whatYouThink, hopingFor }
    public enum Source: Sendable, Equatable { case memory(Memory), idea(Entity) }
    public var source: Source
    public var part: Part
    public var text: String          // decision 6
    public var isOwnWords: Bool      // true: drawn in quotation marks
    public var tags: [String]        // facts only
    public var about: Entity?        // feelings only (decision 4)
    public var telling: Telling?     // nil: no play control
    public var id: String { get }    // "memory:<id>" or "idea:<id>"
}

public struct Portrait: Sendable, Equatable {
    public var owner: Entity?
    public var name: String?
    public var birthLine: String?
    public var strip: LifeStrip?     // nil with no owner or no owner moment
    public var whoYouAre: [PortraitLine]
    public var howItFelt: [PortraitLine]
    public var whatYouThink: [PortraitLine]
    public var hopingFor: [PortraitLine]
    public var leadPool: [PortraitLine] { get }   // decision 8, in part order
    public var isEmpty: Bool { get }              // no line in any part
    public init(_ source: PortraitSource, currentYear: Int)
    public static func birthLine(birthYear: Int?, place: String?) -> String?
    public static func saidWhen(_ toldAt: Date, now: Date, calendar: Calendar = .current) -> String
    /// The kept line while it is still in the pool; else `pick(leadPool.count)`; nil for an empty pool, without calling `pick`.
    public func lead(keeping kept: PortraitLine.ID?, pick: (Int) -> Int) -> PortraitLine?
    /// Decision 12: the tags on `whoYouAre` once each, ignoring case, sorted ignoring case.
    public func tags(leaving lead: PortraitLine.ID?) -> [String]
    /// The part's lines without the lead; for `.whoYouAre`, only those carrying `tag` when it is still in `tags(leaving:)`.
    public func lines(_ part: PortraitLine.Part, leaving lead: PortraitLine.ID?, tag: String?) -> [PortraitLine]
}
```

`saidWhen` uses a `DateFormatter` with `Locale(identifier: "en_GB")` and `dateFormat` "MMMM", or "MMMM yyyy" when the year differs from `now`, as `IdeaTitle.defaultTitle` does.

- [ ] **Step 1: Write the failing tests**

Build `PortraitSource` values by hand; no store. Invented words only.

```swift
@Test func factsAboutYouOrNobodyAreWhoYouAre() {
    // f1 detail → owner; f2 no link; f3 detail → Maya only; f4 mention → Maya, no detail; f5 detail → owner and Maya
    #expect(Portrait(source, currentYear: 2026).whoYouAre.map(\.id) == ["memory:\(f1.id)", "memory:\(f2.id)", "memory:\(f4.id)", "memory:\(f5.id)"])
}
@Test func feelingsAndGoalsShowWhateverTheyAreAbout() {
    #expect(portrait.howItFelt.count == 2 && portrait.hopingFor.count == 1)
}
@Test func aFeelingNamesWhatItIsAboutAndNeverGuesses() {
    // e1: detail → The lake, mention → Alder Street; e2: mention → Jordan (owner) and Maya (hidden); e3: no link
    #expect(portrait.howItFelt.map { $0.about?.title } == ["The lake", nil, nil])
}
@Test func ownWordsAreQuotedAndTitlesAreNot() {
    let lines = Portrait(source, currentYear: 2026).whoYouAre
    #expect(lines[0].text == "I was always the kid who took things apart" && lines[0].isOwnWords)   // stored "um, I was always the kid who took things apart"
    #expect(portrait.whatYouThink[0].text == "Saying yes to things" && !portrait.whatYouThink[0].isOwnWords)
}
@Test func aQuoteOfOnlyFillerShowsTheTitleAndNeverLeads() {
    // f6 title "Something about Ohio", quote "um, uh", with a telling
    let line = portrait.whoYouAre.first { $0.id == "memory:\(f6.id)" }!
    #expect(line.text == "Something about Ohio" && !line.isOwnWords && line.telling != nil)
    #expect(!portrait.leadPool.contains { $0.id == line.id })
}
@Test func theLeadPoolHasOwnWordsAndARecordingInPartOrder() {
    // no ideas, no line without a telling
    #expect(portrait.leadPool.map(\.part) == [.whoYouAre, .whoYouAre, .howItFelt, .hopingFor])
}
@Test func theLeadIsPickedAndKept() {
    var asked: [Int] = []
    let lead = portrait.lead(keeping: nil) { asked.append($0); return 2 }
    #expect(asked == [portrait.leadPool.count] && lead == portrait.leadPool[2])
    #expect(portrait.lead(keeping: lead?.id) { _ in Issue.record("no pick while the lead is kept"); return 0 } == lead)
    #expect(portrait.lead(keeping: "memory:gone") { _ in 0 } == portrait.leadPool[0])
}
@Test func oneLineLeadsAndItsPartHides() {
    let one = Portrait(sourceWithOneFact, currentYear: 2026)
    let lead = one.lead(keeping: nil) { _ in 0 }
    #expect(lead != nil && one.lines(.whoYouAre, leaving: lead?.id, tag: nil).isEmpty)
}
@Test func anEmptyPoolPicksNothing() {
    #expect(Portrait(emptySource, currentYear: 2026).lead(keeping: nil) { _ in Issue.record("no pick"); return 0 } == nil)
    #expect(Portrait(emptySource, currentYear: 2026).isEmpty)
}
@Test func theChipsFilterWhoYouAre() {
    // f1 "Family", f2 "school", f5 "Family" and "family"
    #expect(portrait.tags(leaving: nil) == ["Family", "school"])
    #expect(portrait.lines(.whoYouAre, leaving: nil, tag: "family").map(\.id) == ["memory:\(f1.id)", "memory:\(f5.id)"])
}
@Test func aTagThatIsGoneShowsEverything() {
    #expect(portrait.lines(.whoYouAre, leaving: nil, tag: "Work") == portrait.whoYouAre)
}
@Test func theHeaderSaysOnlyWhatWasTyped() {
    #expect(Portrait.birthLine(birthYear: 1990, place: "Dayton") == "born 1990 in Dayton")
    #expect(Portrait.birthLine(birthYear: 1990, place: nil) == "born 1990")
    #expect(Portrait.birthLine(birthYear: nil, place: " Dayton ") == "born in Dayton")
    #expect(Portrait.birthLine(birthYear: nil, place: "  ") == nil)
    #expect(Portrait(sourceWithEmptyName, currentYear: 2026).name == nil)
}
@Test func theStripIsTheOwnersMoments() {
    // owner moments 1999 and 2000, said; birth 1990
    #expect(portrait.strip?.sentence == "In 2 moments, from 1999 to 2000")
    #expect(Portrait(sourceWithNoOwnerMoments, currentYear: 2026).strip == nil)
}
@Test func aGoalSaysWhenItWasSaid() {
    #expect(Portrait.saidWhen(date(2026, 10, 3), now: date(2026, 11, 16)) == "said in October")
    #expect(Portrait.saidWhen(date(2025, 10, 3), now: date(2026, 11, 16)) == "said in October 2025")
}
```

- [ ] **Step 2: Run `swift test --filter Portrait`.** Expected: FAIL, `Portrait` does not exist.
- [ ] **Step 3: Implement `Portrait.swift`.** Facts, feelings and goals keep `aboutMemories` order sorted by `createdAt`, then id. The strip is `LifeStrip(moments: EntityPage.sections(details: [], mentions: ownerMoments).moments.map(\.range), birthYear: birth?.year, currentYear:)`, and nil when its sentence is nil. `name` is the trimmed `profile.displayName`, else the owner's title, and nil when empty.
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** — `Kit: the portrait's parts, its lead line and its header`

### Task 3: App — the You portrait

**Files:**
- Modify: `ios/Lifeline/UITestSeed.swift` (add `writePortrait`; move `keep` out of `writePeople` into a private static helper both use), `ios/Lifeline/Dependencies.swift` (the `-uiTesting-seedPortrait` line beside `-uiTesting-seedPeople`)
- Modify: `ios/Lifeline/Dependencies.swift` (`pickLead`, in a later commit than the seed)
- Create: `ios/Lifeline/Screens/You/YouViewModel.swift`, `ios/Lifeline/Screens/You/PortraitHeader.swift`, `ios/Lifeline/Screens/You/PortraitPartViews.swift` (the four part views and the chips)
- Modify: `ios/Lifeline/Screens/You/YouScreen.swift`
- Modify: `ios/LifelineUITests/UITestHelpers.swift`, `ios/LifelineUITests/ShellUITests.swift` (`testTheYouTabIsAboutYourself`)
- Test: create `ios/LifelineUITests/YouUITests.swift`

**Interfaces:**
- Consumes: Task 1 `ExtractionStore.portraitSource()`; Task 2 `Portrait`, `PortraitLine`; `LifeStripView`, `EntityScreen`, `EntityViewModel`, `MemoryScreen`, `MemoryViewModel`, `SettingsScreen`, `SessionSubject`, `.sessionContext(_:)`, `home.coverClosings`, `sectionHeadingStyle()`, `FlowLayout`.
- Produces:
  - `UITestSeed.writePortrait(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository) throws`, under `-uiTesting-seedPortrait`. It calls `writePeople`, then saves the profile again with `birthPlaceText: "Dayton"`, then keeps, in this order, in the same session (`seed.m4a`, never written), each with one span of 4 000 ms:
    - fact "Took things apart", quote "um, I was always the kid who took things apart", `detail` → Jordan;
    - fact "The oldest of two", quote "I'm the oldest of two", `detail` → Jordan, tag "Family";
    - fact "Never sat still", quote "I never could sit still in a classroom", no link, tag "School";
    - fact "The hall light", quote "I still sleep with the hall light on", no link, then hidden;
    - fact "Something about Ohio", quote "um, uh", no link;
    - feeling "Leaving Boston", quote "leaving Boston felt like closing a book before the last chapter", no link;
    - feeling "Never scared at the lake", quote "I was never scared at the lake, not once", `detail` → a new place "The lake";
    - goal "Lisbon", quote "I want to take Maya to Lisbon someday", no link.
    The idea "Saying yes to things" from `writePeople` has no span. Maya's and Sam's facts stay `detail` → Maya and Sam.
  - `Dependencies.pickLead: @Sendable (Int) -> Int` (decision 9), set in both factories.
  - `YouViewModel` (`@MainActor @Observable final class`): `init(deps: Dependencies)` does no reads. `private(set) var portrait: Portrait?`, `private(set) var lead: PortraitLine?`, `var tag: String?`, `private(set) var isLoaded = false`, `private(set) var error: String?`, `let deps: Dependencies`. `func refresh(newLead: Bool)`: one `portraitSource()`, then `lead = portrait.lead(keeping: newLead ? nil : lead?.id, pick: deps.pickLead)`. `func lines(_ part: PortraitLine.Part) -> [PortraitLine]` and `var tags: [String]` pass `lead?.id` and `tag` to the kit. `var ownerSubject: SessionSubject?` from `portrait.owner`, with `isOwner: true`.
  - `YouScreen(deps: Dependencies, isSessionLive: @escaping () -> Bool)`: same signature as today. Body, top to bottom, in a `ScrollView` + `VStack` (decision 19), 16-point side margins, on `linenBackground()`:
    1. `PortraitHeader`: the name (`you.name`, serif `.largeTitle`), the birth line (`you.birth`, footnote, `Theme.secondaryText`), and the strip: a `NavigationLink` to the owner's `EntityScreen`, identifier `entities.aboutYou`, holding `LifeStripView(strip:)` and a chevron, accessibility label the strip's sentence.
    2. The lead: the text in curly quotation marks when `isOwnWords`, serif `.title`, `Theme.ink`, identifier `you.lead`, accessibility label the text without marks. Its play control comes in Task 4.
    3. The parts in spec order, each only with lines. Heading text with `sectionHeadingStyle()`. "Who you are": the chips when `tags` is not empty (a `FlowLayout`; "All" is `you.tag.all`, each tag is `you.tag` with the tag as label), then rows. A fact or goal row: a `NavigationLink` to its `MemoryScreen`, identifier `you.line`, label `line.text`, the text in serif `.body` (in marks when `isOwnWords`), under it the tags (fact) or `Portrait.saidWhen` (goal) in footnote `Theme.secondaryText`, set as the accessibility value. A feeling row: a card on `Theme.sand`, italic serif text (`you.line`), then "about {title}" as a `NavigationLink` to that page (`you.feelingAbout`). An idea row: serif `.title2` text beside a 3-point `Theme.ochre` rule, a `NavigationLink` to its `EntityScreen`, identifier `entities.row`, label the title.
    4. The invitation (`you.invite`, `EntityPage.invitation(title: "", isOwner: true)`) only when `isLoaded` and `portrait.isEmpty`.
    5. The error (`you.error`, red) when set.
    - `.navigationTitle("You")`, `.navigationBarTitleDisplayMode(.inline)`; toolbar "Settings" (`home.settings`) opens `SettingsScreen` as today; its `onDismiss` calls `refresh(newLead: false)`. `.onAppear { isVisible = true; viewModel.refresh(newLead: true) }`, `.onDisappear { isVisible = false }`, `.onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh(newLead: false) } }`, `.sessionContext(viewModel.ownerSubject)`.
  - In `UITestHelpers.swift`, on `XCUIApplication`: `static func launchWithPortrait(_ extra: [String] = []) -> XCUIApplication` (as `launchWithPeople`, with `-uiTesting-seedPortrait`), `func openYou()` (opens the You tab and waits for `you.name`), `func youLineLabels() -> [String]` (the `you.line` labels, top to bottom).

- [ ] **Step 1: Add the seed and commit it alone.** The commit touches only `UITestSeed.swift` and the one launch-argument line in `Dependencies.swift`. It uses only APIs that exist at `4609a3c`, so Task 6 can cherry-pick it for the "before" screenshots.

```bash
git add ios/Lifeline/UITestSeed.swift ios/Lifeline/Dependencies.swift
git commit -m "UI tests: an invented portrait to seed the You tab"
```

- [ ] **Step 2: Add the helpers, then write the failing UI tests**

```swift
final class YouUITests: XCTestCase {
    @MainActor
    func testThePortraitReadsInTheSpecOrder() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        XCTAssertEqual(app.staticTexts["you.name"].label, "Jordan")
        XCTAssertEqual(app.staticTexts["you.birth"].label, "born 1990 in Dayton")
        XCTAssertEqual(app.buttons["entities.aboutYou"].label, "In 2 moments, from 1999 to 2000")
        XCTAssertEqual(app.staticTexts["you.lead"].label, "I was always the kid who took things apart", "pickLead is 0 under test")
        XCTAssertEqual(app.youLineLabels(), ["I'm the oldest of two", "I never could sit still in a classroom", "Something about Ohio",
                                             "Leaving Boston felt like closing a book before the last chapter",
                                             "I was never scared at the lake, not once", "I want to take Maya to Lisbon someday"])
        XCTAssertFalse(app.buttons["Two years younger than me"].exists, "a fact about Maya is on her page, not here")
        XCTAssertFalse(app.buttons["I still sleep with the hall light on"].exists, "a hidden fact never shows")
        XCTAssertFalse(app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I was always the kid who took things apart")).firstMatch.exists, "the lead does not repeat")
        let headings = ["Who you are", "How it felt", "What you think", "What you're hoping for"].map { app.staticTexts[$0] }
        XCTAssertTrue(headings.allSatisfy(\.exists))
        XCTAssertEqual(headings.map(\.frame.minY), headings.map(\.frame.minY).sorted(), "the parts in spec order")
        XCTAssertLessThan(app.staticTexts["you.lead"].frame.minY, headings[0].frame.minY)
        XCTAssertEqual(app.buttons.matching(identifier: "you.feelingAbout").firstMatch.label, "about The lake")
        XCTAssertEqual(app.buttons.matching(identifier: "entities.row").firstMatch.label, "Saying yes to things")
        XCTAssertFalse(app.any("you.invite").exists)
    }
    @MainActor
    func testTheChipsFilterWhoYouAre() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        XCTAssertEqual(app.buttons.matching(identifier: "you.tag").allElementsBoundByIndex.map(\.label), ["Family", "School"])
        app.buttons.matching(identifier: "you.tag").matching(NSPredicate(format: "label == %@", "Family")).firstMatch.tap()
        XCTAssertEqual(app.youLineLabels(), ["I'm the oldest of two",
                                             "Leaving Boston felt like closing a book before the last chapter",
                                             "I was never scared at the lake, not once", "I want to take Maya to Lisbon someday"],
                       "the chip filters Who you are only")
        XCTAssertTrue(app.buttons.matching(identifier: "you.tag").matching(NSPredicate(format: "label == %@", "Family")).firstMatch.isSelected)
        app.buttons["you.tag.all"].tap()
        XCTAssertTrue(app.buttons["I never could sit still in a classroom"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testAFeelingOpensWhatItIsAbout() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        app.buttons["you.feelingAbout"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "The lake")
    }
    @MainActor
    func testALineOpensItsMemory() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        app.buttons.matching(identifier: "you.line").firstMatch.tap()
        XCTAssertTrue(app.any("memory.kind").waitForExistence(timeout: 5))
    }
    @MainActor
    func testAYouPageWithNothingToldInvitesAStory() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]; app.launch(); app.skipFirstOpen()   // an owner, nothing told
        app.openTab("You")
        XCTAssertTrue(app.any("you.invite").waitForExistence(timeout: 5))
        XCTAssertEqual(app.any("you.invite").label, "Stories you tell about yourself will show here.")
        for absent in ["Who you are", "How it felt", "What you're hoping for"] { XCTAssertFalse(app.staticTexts[absent].exists) }
        XCTAssertFalse(app.any("you.lead").exists)
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story about yourself")
        XCTAssertTrue(app.buttons["home.settings"].exists)
    }
    @MainActor
    func testTheLargestTextSizeKeepsEveryLine() {
        let app = XCUIApplication.launchWithPortrait(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.openYou()
        XCTAssertEqual(app.youLineLabels().count, 6)
        let lead = app.staticTexts["you.lead"]
        XCTAssertGreaterThan(lead.frame.height, 120, "the lead wraps onto several lines, never truncates")
        for chip in app.buttons.matching(identifier: "you.tag").allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(chip.frame.height, 44) }
    }
}
```

`ShellUITests.testTheYouTabIsAboutYourself` moves to `XCUIApplication.launchWithPeople()`, because the owner's page is now reached through the strip and Jordan has two moments there. The assertions stay: the bar reads "Tell a story about yourself" on the You root, on the owner's page after tapping `entities.aboutYou`, and again after going back; it reads "Tell a story" on Places.

- [ ] **Step 3: Run `-only-testing:LifelineUITests/YouUITests`.** Expected: FAIL, `you.name` does not exist.
- [ ] **Step 4: Add `pickLead`, `YouViewModel`, `PortraitHeader`, the part views, and the new `YouScreen` body.** Run `xcodegen generate` after adding the files. Draw the chip and the strip link with system button styles: a chip is `.buttonStyle(.bordered)`, `.buttonBorderShape(.capsule)`, `.tint(Theme.oliveOnFill)`, and the selected one `.borderedProminent` with `.tint(Theme.olive)`, a `checkmark` symbol and `.accessibilityAddTraits(.isSelected)`; each has `.frame(minHeight: 44)` inside its label.
- [ ] **Step 5: Run `swift test`, then `-only-testing:LifelineUITests/YouUITests -only-testing:LifelineUITests/ShellUITests -only-testing:LifelineUITests/EntitiesUITests -only-testing:LifelineUITests/EntityPageUITests`.** Expected: PASS. `EntitiesUITests` and `EntityPageUITests` still find the ideas on You as `entities.row`.
- [ ] **Step 6: Commit** — `You: a portrait in your own words, with the parts the spec names` (with the helpers, `YouUITests.swift` and the `ShellUITests` change)

### Task 4: App — every line plays

**Files:**
- Modify: `ios/Lifeline/Screens/You/YouViewModel.swift`, `ios/Lifeline/Screens/You/PortraitPartViews.swift`, `ios/Lifeline/Screens/You/YouScreen.swift`
- Modify: `ios/Lifeline/Dependencies.swift` (`audioURL(for: Telling)`)
- Test: `ios/LifelineUITests/YouUITests.swift`

**Interfaces:**
- Consumes: Task 1 `Telling`; Task 3 `YouViewModel`, the rows; `SegmentPlayer`, `deps.activatePlayback()`, `Format.duration(ms:)`.
- Produces:
  - `Dependencies.audioURL(for telling: Telling) throws -> URL`: `AudioLocation.directory(under: audioRoot).appending(path: telling.audioPath)`, as `audioURL(for: Session)`.
  - On `YouViewModel`: `let player = SegmentPlayer()`, `private(set) var playingLineID: PortraitLine.ID?`, `func togglePlayback(_ line: PortraitLine)`, `func isPlaying(_ line: PortraitLine) -> Bool` (`playingLineID == line.id && player.playingRange != nil`), `func stop()`. A second tap on the playing line stops it; a tap on another line plays that one instead. A failure sets `error` to "Could not play this: \(error.localizedDescription)" and changes nothing else.
  - `PlayLineButton(line: PortraitLine, viewModel: YouViewModel)`: shown only when `line.telling != nil`. A `play.circle` symbol (`stop.circle` while playing) in `.title2`, `Theme.oliveText`, `.frame(minWidth: 44, minHeight: 44)` inside the label, `.contentShape(Rectangle())`, `.buttonStyle(.borderless)`, identifier `you.play`, accessibility label "Hear yourself say it" or "Stop". It sits after the row's `NavigationLink`, never inside it.
  - The lead's control: `Label("Hear yourself say it, \(Format.duration(ms: range.end - range.start))", systemImage: "play.fill")`, or "Stop" with `stop.fill`, `.buttonStyle(.bordered)`, `.buttonBorderShape(.capsule)`, `.tint(Theme.oliveOnFill)`, `.frame(minHeight: 44)` inside the label, identifier `you.lead.play`. Only when the lead has a telling (always, by decision 8).
  - `YouScreen.onDisappear` also calls `viewModel.stop()`.

- [ ] **Step 1: Write the failing UI tests**

```swift
@MainActor
func testEveryLineWithARecordingHasAPlayControl() {
    let app = XCUIApplication.launchWithPortrait(); app.openYou()
    XCTAssertEqual(app.buttons["you.lead.play"].label, "Hear yourself say it, 0:04")
    XCTAssertEqual(app.buttons.matching(identifier: "you.play").count, 6, "six lines with a recording; the idea has none")
    XCTAssertEqual(app.buttons.matching(identifier: "you.play").firstMatch.label, "Hear yourself say it")
}
@MainActor
func testEveryPlayControlIsFullSize() {
    let app = XCUIApplication.launchWithPortrait(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.openYou()
    for play in app.buttons.matching(identifier: "you.play").allElementsBoundByIndex {
        XCTAssertGreaterThanOrEqual(play.frame.width, 44); XCTAssertGreaterThanOrEqual(play.frame.height, 44)
    }
    XCTAssertGreaterThanOrEqual(app.buttons["you.lead.play"].frame.height, 44)
}
@MainActor
func testAMissingRecordingSaysSoAndKeepsThePage() {
    let app = XCUIApplication.launchWithPortrait(); app.openYou()   // the seed never writes seed.m4a
    app.buttons.matching(identifier: "you.play").firstMatch.tap()
    let error = app.any("you.error")
    XCTAssertTrue(error.waitForExistence(timeout: 5))
    XCTAssertTrue(error.label.hasPrefix("Could not play this: "))
    XCTAssertEqual(app.youLineLabels().count, 6, "the page stays as it was")
    XCTAssertEqual(app.buttons.matching(identifier: "you.play").firstMatch.label, "Hear yourself say it", "nothing is playing")
}
```

- [ ] **Step 2: Run `-only-testing:LifelineUITests/YouUITests`.** Expected: FAIL, `you.play` does not exist.
- [ ] **Step 3: Implement the play controls as the Interfaces block says.**
- [ ] **Step 4: Run `swift test`, then `-only-testing:LifelineUITests/YouUITests`.** Expected: PASS.
- [ ] **Step 5: Commit** — `You: every line plays the part of the recording where you said it`

### Task 5: App — About leaves Timeline; hide and delete live on You

**Files:**
- Delete: `ios/Lifeline/Screens/Timeline/AboutSection.swift`
- Modify: `ios/Lifeline/Screens/Timeline/TimelineScreen.swift:5,107`, `ios/Lifeline/Screens/Timeline/TimelineViewModel.swift:69,145,157-161,199`
- Modify: `ios/Lifeline/Screens/You/YouViewModel.swift`, `ios/Lifeline/Screens/You/PortraitPartViews.swift`, `ios/Lifeline/Screens/You/YouScreen.swift`
- Test: `ios/LifelineUITests/KindsUITests.swift` (moves; see below), `ios/LifelineUITests/YouUITests.swift`

**Interfaces:**
- Consumes: Task 3 `YouViewModel`, the rows; `deps.actions.setHidden(_:_:)`, `deps.extractionStore.memories.delete(_:)`.
- Produces:
  - `TimelineViewModel.aboutCount: Int` replaces `about: [MemoryRow]`. `memoryCount` and `summaryText(…, about:)` use it (decision 18). No `MemoryRow` is built for a non-moment.
  - On `YouViewModel`: `func hide(_ line: PortraitLine)`, `func delete(_ line: PortraitLine)`, `var deleteTarget: PortraitLine?`. Both act only on `.memory` lines, then `refresh(newLead: false)`. Errors: "Could not hide that: …", "Could not delete that: …".
  - On each fact, feeling and goal row: `.contextMenu { Button("Hide", systemImage: "eye.slash") (you.hide); Button("Delete…", systemImage: "trash", role: .destructive) (you.delete) }`. The lead carries the same menu. `YouScreen` shows the delete `confirmationDialog` with the Global Constraints copy; its button keeps the identifier `row.confirmDelete`.

`KindsUITests.testFactKeptLandsUnderAbout` asserts today's About. It moves to the new behaviour and is renamed `testAFactAboutTheHouseLandsOnItsPage`. The kept fact "The house had a blue door" is a `detail` of the thing "the house" (scripted fact mode), so by decision 2 it is not on You. Every assertion keeps its strength:
- "a kept fact sits under About" becomes: on Timeline, `timeline.about` does not exist; on You, no `you.line` has the label "The house had a blue door"; on Things → "the house", an `entity.detail` button has that label.
- "nobody asks when a fact happened" (`row.addDate` absent) and "the shelf holds moments only" (`timeline.shelf` absent) are checked on Timeline as before.
- From the `entity.detail` button, the memory page, "What is this?" and the move to a moment run as before. After going back, the test opens the Timeline tab and checks the shelf, `row.addDate`, and that `timeline.about` does not exist, as before.

- [ ] **Step 1: Write the failing UI tests**

```swift
// YouUITests
@MainActor
func testALineCanBeHidden() {
    let app = XCUIApplication.launchWithPortrait(); app.openYou()
    let line = app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I'm the oldest of two")).firstMatch
    line.press(forDuration: 1.0)
    app.buttons["you.hide"].tap()
    XCTAssertTrue(line.waitForNonExistence(timeout: 5))
    XCTAssertEqual(app.youLineLabels().count, 5)
}
@MainActor
func testALineIsDeletedOnlyAfterAsking() {
    let app = XCUIApplication.launchWithPortrait(); app.openYou()
    let line = app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I want to take Maya to Lisbon someday")).firstMatch
    line.press(forDuration: 1.0); app.buttons["you.delete"].tap()
    XCTAssertTrue(app.buttons["row.confirmDelete"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["row.confirmDelete"].label, "Delete “Lisbon”")
    app.buttons["row.confirmDelete"].tap()
    XCTAssertTrue(line.waitForNonExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["What you're hoping for"].exists, "a part with nothing does not show")
}
@MainActor
func testAboutIsNotOnTimeline() {
    let app = XCUIApplication.launchWithPortrait(); app.openTab("Timeline")
    XCTAssertTrue(app.any("timeline.summary").waitForExistence(timeout: 5))
    XCTAssertFalse(app.any("timeline.about").exists)
    XCTAssertFalse(app.buttons.matching(identifier: "about.row").firstMatch.exists)
    XCTAssertTrue(app.any("timeline.summary").label.contains("things about your life"), "the summary still counts them")
}
```

Then rewrite `KindsUITests` as described above.

- [ ] **Step 2: Run `-only-testing:LifelineUITests/YouUITests -only-testing:LifelineUITests/KindsUITests`.** Expected: FAIL, `you.hide` does not exist and About is still on Timeline.
- [ ] **Step 3: Remove About from Timeline, add `aboutCount`, and add the context menu and the dialog on You.** Run `xcodegen generate` after deleting `AboutSection.swift`.
- [ ] **Step 4: Run `swift test`, then `-only-testing:LifelineUITests/YouUITests -only-testing:LifelineUITests/KindsUITests -only-testing:LifelineUITests/TimelineUITests -only-testing:LifelineUITests/SameStoryUITests -only-testing:LifelineUITests/EntitiesUITests`.** Expected: PASS.
- [ ] **Step 5: Commit** — `About leaves Timeline; hide and delete a line from You` (body: a fact about another person lands on that page, per S2 decision 17)

### Task 6: Docs, screenshots and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` (the "shape of the app" paragraph, "Not everything is a moment", section 6 "Kinds and entities")
- Modify: `docs/DECISIONS.md` (one entry for S3: decisions 2, 4, 5, 8, 17 and 18)
- Create: `docs/plans/2026-11-16-sections-you-device-check.md`
- Create: `docs/screenshots/sections-you/before-you.png`, `before-timeline-about.png`, `after-you-top.png`, `after-you-further.png`, `after-you-family.png`, `after-you-invite.png`, `after-you-largest-text.png`, `after-timeline.png`

- [ ] **Step 1: Take the "before" screenshots.** Create a temporary worktree: `git worktree add ../lifeline-you-before origin/sections-pages`. Cherry-pick the seed commit from Task 3 Step 1. In both worktrees, add an uncommitted UI test file `ScreenshotTour.swift`. It launches with `-uiTesting -uiTesting-seedPortrait`, opens You (and, before, scrolls Timeline to About), and adds each screen as a kept `XCTAttachment`. After: You at the top, You further down, the "Family" chip, the invitation (`-uiTesting-noOwner`), the largest text size, and Timeline. Run it with `-resultBundlePath`. Export with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`. Copy the images under the names above. Remove the temporary worktree and delete `ScreenshotTour.swift`.
- [ ] **Step 2: Update OVERVIEW.** Describe You as a portrait: the header and strip, the lead line, the four parts and what goes in each (decisions 2 to 5), every line playing its span, the chips, and that About left Timeline while the summary still counts those things. Say that facts about others with no link stay on You until extractor v7.
- [ ] **Step 3: Add the DECISIONS entry**, dated 2026-11-16, in the file's existing format.
- [ ] **Step 4: Write the device checklist.** Each item is one line the owner ticks on the iPhone:
  1. You reads as a portrait in light and dark appearance: name, birth line, strip, lead line, then the parts. No part shows empty.
  2. Open You three times from another tab; the lead line changes, and it never repeats in its part.
  3. Play the lead and two lines; each plays only the words on screen, and a second tap stops it.
  4. With VoiceOver, each line reads its words, then its tag or "said in …", and each play control reads "Hear yourself say it".
  5. At the largest accessibility text size, the lead and every line read in full, and the chips wrap.
  6. A feeling's "about" line opens that page. The strip opens your own page.
  7. On the owner's real archive, list the facts under "Who you are" that are about someone else. They show the extractor's missing links (decision 2) for track A.
  8. Hide a line and delete another; Timeline shows no About section and its summary still counts them.
- [ ] **Step 5: Run `swift test`.** Expected: PASS. Do not run the whole UI suite here; the controller runs it after the final review.
- [ ] **Step 6: Check that `git status` shows no `ios/Config/Local.xcconfig` and no `ScreenshotTour.swift`.**
- [ ] **Step 7: Commit** — `Docs: You as a portrait in the overview, screenshots, and the device checklist`

---

## After S3

S4 (photos) puts photos of the person on the You strip at their years and adds "Add a photo" to You's menu. The way back for a hidden fact, feeling or goal still has no home. Extractor v7 (track A) decides how many facts move off "Who you are". The dark and increased-contrast colour values still have no PR assigned.
