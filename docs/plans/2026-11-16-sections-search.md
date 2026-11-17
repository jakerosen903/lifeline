# S5: Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The tab bar gets a trailing search tab. The person types a name or a word they said. The app shows the people, places, things, ideas and memories that match, grouped by kind. A tap opens the page. Nothing leaves the phone, and the app keeps no record of what was typed.

**Architecture:** Tasks 1 to 3 are pure code in the kit: `SearchFold` (one folded form for the query and for the searched text), `Search.run` (a query and an in-memory `SearchIndex` to grouped, ranked `SearchResults`) and `SearchSnippet` (the person's words around a match). Task 4 adds one batched read, `ExtractionStore.searchIndex()`, that builds the index from the rows the app shows. Task 5 adds the tab, a thin `SearchViewModel`, the screen with the entity results, the seed and the launch argument. Task 6 adds the memory results, the snippet, the "nothing found" state and the refresh after a change. Task 7 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26 (`Tab(value:role:)` with `.search`, `searchable`), GRDB 7 (reads only), Swift Testing, XCUITest. No migration. No new dependency. No network call. No embeddings.

**Spec:** `docs/specs/2026-11-15-five-sections.md`, sections "Shell" (the search tab and the record bar), "Build order" (step 8), "Non-goals and anti-goals", "Appearance and accessibility" and "Left to the builder" (group or rank). The umbrella plan `docs/plans/2026-11-15-sections.md`, "Ship order" and "Rules for the order". `docs/DECISIONS.md`, entries of 2026-11-15 (five tabs and search) and 2026-11-16 (photos: no search result uses a photo yet). `docs/PRINCIPLES.md`, "Session arc and emotional safety" (what Hide and Exclude mean). Mock-up: `docs/design/Sections.html` has one note only ("Search is the round button beside the tabs and covers every section"). It has no search screen. Read all of these before Task 1.

**Worktree and branch:** `/Users/jakerosen/dev/lifeline/lifeline-search`, branch `sections-search`, based on `origin/main` (`a1638c3`, which holds S1 to S4). Work only there.

---

## Decisions made in this plan

The spec leaves these open. Each one is decided here so the owner can overrule it before work starts. A decision that serves a principle names it (P1 to P9, `docs/PRINCIPLES.md`). Copy that this plan invents is marked **(invented copy)**.

1. **The engine is a scan in Swift, not SQLite FTS5.** The app builds an in-memory index when the search tab appears, and scans it on each change of the query. FTS5 is available: the GRDB 7.11.1 package manifest defines `SQLITE_ENABLE_FTS5`. This plan does not use it, for four reasons.
   - **Size.** The tables hold tens to hundreds of rows. A scan answers in less than one frame. An index on disk gives nothing the person can see.
   - **Delete must mean delete.** FTS5 keeps the terms of a deleted row in its segments until a merge. The app promises that Delete removes the content and everything derived from it. A second copy of the person's words on disk is a second thing to remove, to back up and to restore.
   - **The searched text is derived from three tables.** A memory's words are the `word` rows inside its `memory_span` bounds, and a trim moves those bounds. FTS5 needs triggers on `memory`, `entity`, `alias`, `memory_span` and `word`, or a rebuild at launch. A trigger's `DELETE FROM` trips the destructive-migration guard in `.github/scripts/pr_guards.py`. A rebuild at launch is the scan with more parts.
   - **Migrations and copies.** FTS5 needs a migration. Places already expects v14, and the first PR to merge keeps its number. A copy from an older build must rebuild the index after restore, and the launch repair (`ArchiveRepair`) must run before it.
   Cost: every word of every kept memory is read when the tab appears. Device checklist item 7 measures it. If the archive outgrows the scan, FTS5 can replace `Search.run` behind the same `SearchResults` with no change to the views.
2. **No migration.** S5 reads only. `Migrations.swift` and `MigrationsTests.swift` do not change. Backup, restore and the launch repair do not change.
3. **What is searched.** Five kinds, as the spec lists them.
   - A person: the title and the person's aliases (the `alias` table: the other names the owner used). The spec says "titles". Aliases are added because "Mum" must find the person the owner later named. The owner must confirm.
   - A place, a thing, an idea: the title.
   - A memory that is a moment (kind `event` or `other`): the title and the text.
   - A memory that is a fact, a feeling or a goal: the text only. Its stored title shows on no screen (`MemoryLabel.heading` shows the quote), so a match on it would show no matching word. This differs from the spec's "titles of memories". The owner must confirm.
4. **"The text of a memory" is the person's own words.** It is the summary quote, plus the words of each telling: the `word` rows of the span's segment whose times lie inside the span. A span with no `word` rows adds nothing; the quote is still searched. Words outside a trimmed span are not searched, because the person cut them from the memory.
5. **What is not searched.** Words of a recording that are in no kept memory (a card still waiting, a dismissed card, a segment still being sorted). Story, chapter and collection titles. Tags. Dates and years as dates. Names in the "Names you mentioned" queue. The interviewer's words. Photos. The reason for each is in "Limits found while planning".
6. **Hidden is not found. Kept from AI is found.**
   - A memory or an entity with `hidden_from_timeline` is not a result, and a hidden memory adds nothing to a result. Hide means "out of everyday browsing", and search is everyday browsing. The search tab has no "Show hidden" switch. A hidden memory stays reachable from Sessions and from Timeline's "Show hidden memories". (P8: the person's say over what is kept.)
   - A memory or an entity with `excluded_from_ai` is a result like any other. Exclude stops processing by the model and use in context. Search is a comparison of strings on the phone. It sends nothing and uses no model. The owner must confirm this reading.
   - A floating stand-in (`isFloating`) is not a result: the person has not told it. The owner's own entity is not a result, as on People (audit F10).
7. **Matching: every word of the query must start a word of the item.** The query and the text are folded the same way (decision 8) and split into words. An item matches when each query word is the start of some word in the item's searched text. Word order does not matter. "swim" finds "swimming". "art" does not find "party". There is no spelling correction, no stemming and no "did you mean": the app never guesses what the person meant (P1, P5).
8. **Folding.** Lower case. No diacritics. Full-width forms become half-width. An apostrophe (`'`, `’`, `ʼ`) is removed. Every other character that is not a letter or a digit becomes a space. One space between words. So "ZOE" finds "Zoë", "dads volvo" finds "Dad's Volvo", and "st louis" finds "St. Louis". `MatchKey` is not reused: it decides that two names are one, so it keeps symbols ("C++" is not "C#"). Search only finds, so it may fold more.
9. **A query of one character searches titles and aliases only.** One letter starts too many spoken words to be useful. One character can be a whole name in some scripts, so it still searches names.
10. **A long query is cut at 200 characters before folding.** The rest is ignored. An empty query, and a query that folds to nothing ("…", "!!"), show the opening state, not "nothing found".
11. **Results are grouped by kind, not ranked together.** The groups show in this order: "People", "Places", "Things", "What you think", "Memories". A group with no result does not show. Why: a name match and a word match have no honest common score; the entity groups are short and the memory group can be long; a heading for each kind gives VoiceOver a route. "What you think" is the heading the You tab already uses for ideas.
12. **Order inside a group.** By match first: the title equals the query; the title starts with the query; every query word starts a title word; an alias matches (people); the text matches (memories). Then, for people, places, things and ideas: most moments first, then title, then id. For memories: life order, as `EntityPage.ordered` sorts (by the start of the range, and by when it was told with no range), then id. An item shows once, at its best match. There is no cap on a group; the list is lazy.
13. **What a result shows.**
    - A person: the face (the cover photo, or the letter tile, as `TileFace` draws it on People), the name, and the person's own words ("my sister"). When only an alias matched, the alias shows in place of the own words, so the person sees why the row is there.
    - A place, a thing, an idea: the title.
    - A moment: the title. The date under it, from `TimeRange.displayText`, only when the memory is placed. An undated moment shows no date line and no "add a date" (P9).
    - A fact, a feeling or a goal: the cleaned quote in quotation marks (`MemoryLabel.heading`).
    - A memory found by its text: also one line of the person's words around the first match, in quotation marks, as said, not cleaned (`SearchSnippet`). The matched words are semibold. A fact, feeling or goal whose quote holds every query word shows no second line: the heading already shows the words.
    - No row shows a count, a people chip, a place or a "check this" tag.
14. **Uncertainty.** The date line is `displayText`, so a guessed date reads "around 1998" or "sometime between …", in words, never by colour alone (P5). A result shows no other inferred detail. A name the app has not confirmed is a mention in the queue, and the queue is not searched, so no guessed name can be a result.
15. **A tap opens the page, in the search tab's own stack.** A person, place, thing or idea opens `EntityScreen`. A memory opens `MemoryScreen`. Back returns to the results with the query kept. The other tabs do not move.
16. **The record bar stays on the search tab.** On the results it reads "Tell a story". On a page opened from a result it names the page, as on every tab ("Tell a story about Maya"); `EntityScreen` already does this through `sessionContext`. A session started there covers the tabs. When the cover closes, the query is still in the field and the results are read again. (Spec goal 4: telling stays one tap away.)
17. **Stale results.** The index is read again when the search tab appears, when a pushed page reports a change (`onChange`), and when a session cover closes (`home.coverClosings`). So a renamed, merged, hidden or deleted item is right when the person comes back. A result tapped in the moment its item goes opens a page that closes itself (`MemoryViewModel.isGone`, and the entity page's own handling).
18. **A memory still being sorted is not found.** It is not a memory until its card is kept (P9: the recording is safe; a card approves organisation). The "nothing found" copy says what search looks at, so it never claims the words were not said.
19. **No history, no suggestions.** The app keeps no recent searches, writes the query nowhere (no `UserDefaults`, `@AppStorage`, `@SceneStorage` or file), and offers no suggested words. A remembered query could put a hard word back in front of the person (P6). The field turns autocorrection and autocapitalisation off, because names get "corrected".
20. **The opening state.** With an empty field the screen shows one quiet line and nothing else. No list of everything, no count, no tip to add anything (P9).
21. **Copy, all invented by this plan (the spec gives none).**
    - Field prompt: "Memories, people, places, things" **(invented copy)**
    - Opening line: "Search by a name, or by words you said." **(invented copy)**
    - Headings: "People", "Places", "Things", "What you think", "Memories".
    - Nothing found, title: "Nothing found" **(invented copy)**
    - Nothing found, line: "Search looks at names and at the words of memories you kept." **(invented copy)**
    - Read error: "Could not search: {reason}" **(invented copy)**. The reason is the database error. It never holds the query.
    - The tab's title is the system's ("Search").
22. **The index loads off the main actor.** It reads the `word` table, which is the largest in the archive. `SearchViewModel` does no read in `init` and exposes `isLoaded`. A query typed before the index is ready runs when it is.
23. **A person result may use the cover photo.** The S4 decision said no search result uses a photo "yet (S5 to S8)". This plan shows the cover in the face, the same way People does, and adds nothing else from a photo.
24. **`AppTab` gains `search`.** `AppTab.sections` lists the five sections for the `ForEach`; the search tab is declared after them with `role: .search`. Its accessibility identifier is `tab.search`.
25. **A test seed and its own simulator.** `-uiTesting-seedSearch` writes the invented family (`people(…)`) and the rows the search tests need. UI tests in this worktree run on a simulator made for it.
26. **VoiceOver.** Each result is one button. Its label is the first line. Its value is the second and third lines. Each group heading is a header. When a query finds nothing, the title "Nothing found" is announced once.

### Limits found while planning

- **The mock-up has no search screen.** `Sections.html` says only that search is the round button beside the tabs. Decisions 11, 13, 20 and 21 are this plan's design. The owner must look at the Task 7 screenshots.
- **The system owns the search tab's chrome.** On iOS 26 a tab with `role: .search` is drawn apart from the others, and the field's place is the system's choice. How the bottom accessory (the record bar) sits with the field and the keyboard is not documented well enough to plan. Task 5 verifies it in the simulator. If the system does not show the accessory on the search tab at all, stop and ask the owner. Do not draw a second bar.
- **Words in no kept memory are not found.** A story told a minute ago is found only after its card is kept. The recording is in Sessions. Search over session transcripts is a possible later step ("After S5").
- **Stories, chapters and collections are not found by their titles.** The spec lists five kinds and none of these. A story and a collection have no page to open. The Timeline plan (S6) is changing chapters.
- **A year is not a date to search.** "1999" finds a title or a spoken "1999". It does not find a memory by its range.
- **No tolerance for spelling.** "treehouse" does not find "tree house". The speech-to-text spelling of a name is what is stored, and it can be wrong. Renaming the person or place fixes the title.
- **Scripts without spaces.** Word-start matching finds only the start of a run in Chinese or Japanese text. The app's copy and speech are English today.
- **Dictation into the field is the system's.** The app adds no microphone to the field. The system keyboard's own dictation follows the phone's settings.
- **Other worktrees.** Other branches add launch arguments in `Dependencies.swift` and seeds in `UITestSeed.swift`. Expect a small merge conflict in both files. Keep both sides.
- **Its own simulator.** UI tests time out when two builds use one simulator. Create one for this worktree: `xcrun simctl create "Lifeline Search" "iPhone 17 Pro"`. Pass its id to `-destination`. Do not use `88EC5B09-3A30-4544-8145-F5246BB99AEE`.
- **Dark and increased-contrast values** still have no PR. S5 adds no colour value.

### Where the spec did not fit the code

- "The titles of memories": a fact, feeling or goal has a stored title that no screen shows (decision 3).
- "The text of memories": the store has no such column. It is the quote plus the words inside the spans (decision 4).
- "Titles of people": a person also has aliases (decision 3).
- Build-order step 8 says search needs only the shell. The code on `main` also has `EntityRepository.summaries`, `TileFace` and `PhotoRepository.covers` (S2, S4). This plan uses them.
- "Appearance and accessibility" says the dark values are defined in the plan's first step. They are not on `main`.

---

## Global Constraints

- Deployment target iOS 26.0. Swift 6 with complete strict concurrency. Verify `Tab(value:role:content:)` with `.search`, `searchable(text:placement:prompt:)` and `tabViewSearchActivation(_:)` against the current SwiftUI documentation before use. Do not rely on memory for their signatures.
- No migration. No file under `Store/` changes except the new `SearchReads.swift`. S5 writes no row.
- **Privacy.** No network call. No model call. No embedding. New code must not log, print or persist the query, a title, a quote or a word: no `print`, `Logger`, `os_log`, `NSLog`, `UserDefaults`, `@AppStorage`, `@SceneStorage` or file write. An error message must not hold the query. Each task ends with `git grep -nE "print\(|Logger|os_log|NSLog|URLSession|UserDefaults|AppStorage|SceneStorage" -- <the task's new files>`, which must print nothing.
- Hidden rows are never results (decision 6). Nothing inferred shows as fact (non-negotiable 3, P5).
- No count, no queue, no "add" control, no empty frame on the search tab (P9).
- Copy, exact: decision 21. Headings and their order: decision 11.
- Results show the person's titles and words as stored. The snippet is not cleaned and not paraphrased (P1).
- Pure logic lives in `LifelineKit/Domain/` with Swift Testing tests. One responsibility for each file. The view model holds no matching rule.
- The view model does no read in `init` and exposes `isLoaded`. The index is read in a fixed number of statements, whatever the archive's size.
- Text colours: `Theme.ink`, `Theme.secondaryText`, `Theme.oliveText`, `Theme.ochreText`. Headings use `sectionHeadingStyle()`. Every text colour reaches 4.5:1 on its surface. A match is marked by weight, never by colour alone. No new colour value.
- Every control is at least 44 by 44 points, with the frame and `contentShape` inside the link's label. Text uses text styles (footnote or larger), so it follows Dynamic Type. Rows wrap; nothing is cut at the largest accessibility size.
- Keep these accessibility identifiers: `home.start`, `home.more`, `home.settleIn`, `tab.timeline`, `tab.people`, `tab.places`, `tab.things`, `tab.you`, `entities.row`, `entity.title`, `entity.more`, `entity.rename`, `memory.range`, `memory.change`. New ones: `tab.search`, `search.prompt`, `search.heading`, `search.result`, `search.none`, `search.error`.
- Kit tests: `cd ios/LifelineKit && swift test`. They run in full at every task.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'id=<the "Lifeline Search" simulator id>' -only-testing:LifelineUITests/<Class>`. Each task names the classes it runs. The task report gives the verbatim `Executed N tests, with M failures` line for each class. The whole UI suite runs once, by the controller, after the final review's fixes. No task runs it.
- Real TDD: each new test is seen failing before the code that makes it pass.
- No test's assertion is weakened. No existing test asserts behaviour this plan changes: `ShellUITests.testFiveLabeledTabs` names the five tabs and still passes.
- Fixtures are invented; never a real person's words, names or places.
- `ios/Config/Local.xcconfig` is never committed.
- Commit messages are imperative and one line, with a body when the why is not obvious. No AI attribution lines. Nothing is pushed.
- Docs under `docs/` use ASD-STE100 style.

## Review Focus

1. **Nothing hidden leaks.** A hidden memory, a hidden entity, a stand-in and the owner are in no result, and a hidden memory's words find nothing. Task 4 (`aHiddenMemoryIsNotInTheIndex`, `aHiddenEntityIsNotInTheIndex`, `aStandInAndTheOwnerAreNotInTheIndex`) and Task 6 (`testAHiddenMemoryIsNotFound`).
2. **Nothing typed is kept or sent.** The grep in Global Constraints prints nothing for every new file. Relaunch shows an empty field. Task 5 (`testTheQueryIsGoneAfterARelaunch`).
3. **Only the memory's own words are searched.** Words outside a trimmed span, and words of a segment with no kept memory, find nothing. Task 4 (`wordsOutsideTheSpanAreNotInTheIndex`, `aSegmentWithNoKeptMemoryIsNotInTheIndex`).
4. **A guess reads as a guess.** Task 2 (`aGuessedDateKeepsItsWords`) and Task 6 (`testAGuessedDateReadsAsAGuess`).
5. **Results follow a change.** A rename, a merge, a hide and a delete are right on return. Task 4 (`aMergedEntityIsOneEntry`) and Task 6 (`testARenameShowsOnReturn`, `testADeletedMemoryLeavesTheResults`).
6. **The edges of the query.** Empty, one character, punctuation only, 10 000 characters, diacritics, apostrophes. Tasks 1 and 2.

---

### Task 1: Kit — one folded form for the query and the text

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/SearchFold.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/SearchFoldTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
/// The form search compares: decision 8. The stored text never changes.
public enum SearchFold {
    public static let maxQueryLength = 200
    /// Lower case, no diacritics, half-width, apostrophes removed, every other non-letter and non-digit a space, one space between words.
    public static func fold(_ text: String) -> String
    /// The folded words of a text, in order.
    public static func words(_ text: String) -> [String]
    /// The folded words of a query: cut at `maxQueryLength` characters first. Empty when the query has no letter or digit.
    public static func queryWords(_ query: String) -> [String]
}
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func caseAndDiacriticsFold() {
    #expect(SearchFold.fold("Zoë") == "zoe")
    #expect(SearchFold.fold("SÃO Paulo") == "sao paulo")
    #expect(SearchFold.fold("ＭＡＹＡ") == "maya", "full-width letters")
}
@Test func anApostropheJoinsAndOtherMarksSplit() {
    #expect(SearchFold.fold("Dad's Volvo") == "dads volvo")
    #expect(SearchFold.fold("Dad\u{2019}s Volvo") == "dads volvo", "a curly apostrophe")
    #expect(SearchFold.fold("St. Louis") == "st louis")
    #expect(SearchFold.fold("tree-house, 1999!") == "tree house 1999")
    #expect(SearchFold.fold("  the\n lake \t") == "the lake")
}
@Test func aTextWithNoLetterOrDigitFoldsToNothing() {
    for text in ["", "   ", "…", "!!", "'", "— —"] { #expect(SearchFold.queryWords(text).isEmpty) }
}
@Test func aLongQueryIsCutBeforeFolding() {
    let long = String(repeating: "lake ", count: 2_000)          // 10 000 characters
    #expect(SearchFold.queryWords(long).count == 40, "200 characters hold 40 words")
    #expect(SearchFold.queryWords(String(repeating: "x", count: 10_000)) == [String(repeating: "x", count: 200)])
}
@Test func wordsKeepTheirOrder() {
    #expect(SearchFold.words("Maya's graduation, in Ohio.") == ["mayas", "graduation", "in", "ohio"])
}
@Test func anEmojiIsNotAWord() {
    #expect(SearchFold.words("the lake 🌊") == ["the", "lake"])
}
```

- [ ] **Step 2: Run `cd ios/LifelineKit && swift test --filter SearchFold`.** Expected: FAIL; `SearchFold` does not exist.
- [ ] **Step 3: Implement.** Fold with `String.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)`, so the result does not depend on the phone's language. Classify characters with `Character.isLetter` and `Character.isNumber`. The cut at 200 counts `Character`s, so it never splits one.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole kit suite. Run the privacy grep on the new file.
- [ ] **Step 5: Commit** — `Kit: one folded form for a search query and the text it reads`

### Task 2: Kit — a query and an index to grouped, ranked results

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/SearchIndex.swift` (the entries), `ios/LifelineKit/Sources/LifelineKit/Domain/SearchResults.swift` (the hits and the groups), `ios/LifelineKit/Sources/LifelineKit/Domain/Search.swift` (`Search.run`)
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/SearchTests.swift`

**Interfaces:**
- Consumes: Task 1 `SearchFold`; `EntitySummary`, `Entity`, `EntityType`, `Memory`, `MemoryLabel`, `EntityPage.ordered`, `TimeRange.displayText`.
- Produces:

```swift
/// Everything search reads, in memory. Built by `ExtractionStore.searchIndex()` (Task 4) or by a test.
public struct SearchIndex: Sendable, Equatable {
    public struct EntityEntry: Sendable, Equatable {
        public var summary: EntitySummary
        /// A person's other names. Empty for a place, a thing or an idea.
        public var aliases: [String]
        public init(summary: EntitySummary, aliases: [String] = [])
    }
    public struct MemoryEntry: Sendable, Equatable {
        public var memory: Memory
        /// The words of each telling, as said, first telling first. Empty when the store has no word rows.
        public var tellings: [String]
        /// The session's `started_at` of the first telling, for life order with no date.
        public var toldAt: Date?
        public init(memory: Memory, tellings: [String] = [], toldAt: Date? = nil)
    }
    public var entities: [EntityEntry]
    public var memories: [MemoryEntry]
    public init(entities: [EntityEntry] = [], memories: [MemoryEntry] = [])
    public static let empty = SearchIndex()
}

/// How an item matched, best first (decision 12).
public enum SearchMatch: Int, Sendable, Comparable { case exactTitle, titleStart, titleWords, alias, text }

public struct SearchResults: Sendable, Equatable {
    public struct EntityHit: Sendable, Equatable, Identifiable {
        public var summary: EntitySummary; public var match: SearchMatch
        /// Set only when `match` is `.alias`: the alias that matched, as stored.
        public var matchedAlias: String?
        public var id: EntityID { get }
        /// The row's second line: the matched alias, else the own words (decision 13).
        public var secondLine: String? { get }
    }
    public struct MemoryHit: Sendable, Equatable, Identifiable {
        public var memory: Memory; public var match: SearchMatch
        /// The text the match was found in: the quote, or the first telling that holds every query word. Nil for a title match.
        public var matchedText: String?
        public var id: MemoryID { get }
        /// `MemoryLabel.heading(for:)`.
        public var heading: String { get }
        /// `range.displayText` for a placed moment. Nil for an undated moment and for a fact, feeling or goal.
        public var dateText: String? { get }
    }
    public var people: [EntityHit]; public var places: [EntityHit]; public var things: [EntityHit]; public var ideas: [EntityHit]
    public var memories: [MemoryHit]
    public var isEmpty: Bool { get }
    public static func heading(_ type: EntityType) -> String      // "People", "Places", "Things", "What you think"
    public static let memoriesHeading = "Memories"
}

public enum Search {
    /// Nil when the query has no letter or digit: the opening state, not "nothing found".
    public static func run(_ query: String, in index: SearchIndex) -> SearchResults?
}
```

- [ ] **Step 1: Write the failing tests**

Fixtures are built in the test file with invented people (Maya "my sister", Dad, Zoë, Lena, Sasha, two people named Sam), places (Alder Street, São Paulo), a thing (Dad's Volvo), an idea (Saying yes to things) and memories. `entry(_:type:moments:ownWords:aliases:)` and `memory(_:kind:quote:tellings:range:toldAt:)` are small helpers there.

```swift
// The query's edges
@Test func anEmptyQueryIsNotASearch() {
    for query in ["", "  ", "…", "'"] { #expect(Search.run(query, in: index) == nil) }
}
@Test func aQueryThatFindsNothingIsEmptyNotNil() {
    #expect(Search.run("xylophone", in: index)?.isEmpty == true)
}
@Test func anEmptyIndexFindsNothing() {
    #expect(Search.run("maya", in: .empty)?.isEmpty == true)
}
@Test func aVeryLongQueryAnswers() {
    #expect(Search.run(String(repeating: "lake ", count: 2_000), in: index) != nil)
}
@Test func oneCharacterSearchesNamesOnly() {
    // "The tree house" has the telling "a rope and a ladder"; Alder Street starts with "a".
    let found = try #require(Search.run("a", in: index))
    #expect(found.places.map(\.summary.entity.title) == ["Alder Street"])
    #expect(found.memories.allSatisfy { $0.match < .text }, "no memory by its words")
}

// Matching
@Test func caseAndDiacriticsDoNotMatter() {
    #expect(Search.run("ZOE", in: index)?.people.map(\.summary.entity.title) == ["Zoë"])
    #expect(Search.run("sao", in: index)?.places.map(\.summary.entity.title) == ["São Paulo"])
}
@Test func punctuationDoesNotMatter() {
    #expect(Search.run("dads volvo", in: index)?.things.map(\.summary.entity.title) == ["Dad's Volvo"])
    #expect(Search.run("Dad's Volvo!", in: index)?.things.count == 1)
}
@Test func everyWordMustMatchInAnyOrder() {
    #expect(Search.run("volvo dad", in: index)?.things.count == 1)
    #expect(Search.run("volvo maya", in: index)?.things.isEmpty == true)
}
@Test func aWordMatchesFromItsStartOnly() {
    #expect(Search.run("swim", in: index)?.memories.map(\.memory.title) == ["Swimming lessons"])
    #expect(Search.run("art", in: index)?.memories.isEmpty == true, "not inside \"party\"")
    #expect(Search.run("treehouse", in: index)?.memories.isEmpty == true, "no spelling tolerance (decision 7)")
}

// Kinds
@Test func aPersonIsFoundByAnAliasAndSaysWhich() {
    // Lena has the alias "Linny" and the own words "my aunt".
    let hit = try #require(Search.run("linny", in: index)?.people.first)
    #expect(hit.match == .alias && hit.matchedAlias == "Linny" && hit.secondLine == "Linny")
    #expect(Search.run("lena", in: index)?.people.first?.secondLine == "my aunt")
}
@Test func aTitleMatchBeatsAnAliasMatchAndShowsOnce() {
    // Maya also has the alias "May".
    #expect(Search.run("may", in: index)?.people.map(\.match) == [.titleStart])
}
@Test func twoPeopleWithOneNameBothShow() {
    // Sam "my roommate" has 3 moments; Sam "my cousin" has 1.
    #expect(Search.run("sam", in: index)?.people.map(\.secondLine) == ["my roommate", "my cousin"])
}
@Test func aFactIsFoundByItsWordsNotItsHiddenTitle() {
    // fact, stored title "Took things apart", quote "I was always the kid who dismantled radios"
    #expect(Search.run("took", in: index)?.memories.isEmpty == true)
    #expect(Search.run("radios", in: index)?.memories.map(\.heading) == ["\u{201C}I was always the kid who dismantled radios\u{201D}"])
}
@Test func aMomentIsFoundByItsWords() {
    // "The long drive", telling "he kept an old harmonica in the glove box"
    let hit = try #require(Search.run("harmonica glove", in: index)?.memories.first)
    #expect(hit.memory.title == "The long drive" && hit.match == .text)
    #expect(hit.matchedText == "he kept an old harmonica in the glove box")
}
@Test func aRetoldMemoryShowsOnce() {
    // two tellings both say "harmonica"
    #expect(Search.run("harmonica", in: index)?.memories.filter { $0.memory.title == "The long drive" }.count == 1)
}
@Test func theQueryWordsMayBeSplitBetweenTitleAndWords() {
    #expect(Search.run("drive harmonica", in: index)?.memories.map(\.memory.title) == ["The long drive"])
}

// Order
@Test func matchesOrderByHowTheyMatched() {
    // titles "Lake", "Lake Erie", "The lake in 1999"; a memory whose words say "lake"
    #expect(Search.run("lake", in: lakes)?.memories.map(\.match) == [.exactTitle, .titleStart, .titleWords, .text])
}
@Test func entitiesWithOneMatchGoMostToldFirstThenByTitle() {
    #expect(Search.run("s", in: index)?.people.map(\.summary.entity.title) == ["Sam", "Sam", "Sasha"])   // 3, 1 and 1 moments
}
@Test func memoriesWithOneMatchGoInLifeOrder() {
    // three text matches: dated 2003, dated 1999, undated and told last
    #expect(Search.run("harmonica", in: ordered)?.memories.map(\.memory.title) == ["1999 one", "2003 one", "Undated one"])
}
@Test func theOrderNeverVaries() {
    #expect(Search.run("s", in: index) == Search.run("s", in: SearchIndex(entities: index.entities.reversed(), memories: index.memories.reversed())))
}

// What a hit says
@Test func aGuessedDateKeepsItsWords() {
    // "The red kite", range .year(1998, origin: .inferred, evidence: nil)
    #expect(Search.run("kite", in: index)?.memories.first?.dateText == "around 1998")
}
@Test func anUndatedMomentHasNoDateLine() {
    #expect(Search.run("undated", in: ordered)?.memories.first?.dateText == nil)
}
@Test func aFactHasNoDateLine() {
    #expect(Search.run("radios", in: index)?.memories.first?.dateText == nil, "a fact's stored range is not shown (M7)")
}
@Test func groupsAndTheirHeadings() {
    #expect(EntityType.allCases.map(SearchResults.heading) == ["People", "Places", "Things", "What you think"])
    let found = try #require(Search.run("dad", in: index))
    #expect(found.people.count == 1 && found.things.count == 1, "Dad and Dad's Volvo, each in its group")
}
```

- [ ] **Step 2: Run `swift test --filter "SearchTests"`.** Expected: FAIL; `Search` does not exist.
- [ ] **Step 3: Implement.** `Search.run` folds each entry once per call (the index is small; no cache). A memory's title is searched only when `memory.isMoment`. Its text is the quote, then each telling. With one query word of one character, skip every text. The match of a memory is the best of: title equals, title starts, every word starts a title word, else `.text` when every query word starts a word in the title or the text taken together. `matchedText` is the quote when it holds every query word, else the first telling that does, else the first telling that holds any. Sorting uses the keys of decision 12, ending on the id, so equal items never swap. `Search.run` does not filter hidden rows: the index never holds them (Task 4), and `SearchIndex` built by a test says what it holds.
- [ ] **Step 4: Run `swift test`.** Expected: PASS. Run the privacy grep on the new files.
- [ ] **Step 5: Commit** — `Kit: search an index by word starts, grouped by kind and ordered by match`

### Task 3: Kit — the person's words around a match

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/SearchSnippet.swift`
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/SearchSnippetTests.swift`

**Interfaces:**
- Consumes: Task 1 `SearchFold`; Task 2 `SearchResults.MemoryHit`.
- Produces:

```swift
/// A line of the person's words around the first match, as said (P1). Display only.
public struct SearchSnippet: Sendable, Equatable {
    public struct Part: Sendable, Equatable { public var text: String; public var isMatch: Bool }
    /// In reading order. Joined, they are the snippet with its quotation marks and any "…".
    public var parts: [Part]
    public var text: String { get }
    public static let wordsBefore = 6
    public static let wordsAfter = 7
    /// Nil when no word of `text` starts with a query word.
    public static func around(_ text: String, query: String) -> SearchSnippet?
    /// Nil for a title match, and for a fact, feeling or goal whose quote holds every query word (decision 13).
    public static func line(for hit: SearchResults.MemoryHit, query: String) -> SearchSnippet?
}
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theSnippetCentresOnTheFirstMatch() {
    let said = "we drove all night through Ohio and he kept an old harmonica in the glove box the whole way to the coast"
    let snippet = try #require(SearchSnippet.around(said, query: "harmonica"))
    #expect(snippet.text == "\u{201C}…Ohio and he kept an old harmonica in the glove box the whole way…\u{201D}")
    #expect(snippet.parts.filter(\.isMatch).map(\.text) == ["harmonica"])
}
@Test func aShortTextIsShownWhole() {
    #expect(SearchSnippet.around("an old harmonica", query: "harm")?.text == "\u{201C}an old harmonica\u{201D}")
}
@Test func everyMatchedWordInTheWindowIsMarked() {
    #expect(SearchSnippet.around("the glove box held a harmonica", query: "harmonica glove")?.parts.filter(\.isMatch).map(\.text) == ["glove", "harmonica"])
}
@Test func theWordsAreAsSaidNotCleaned() {
    #expect(SearchSnippet.around("um, it was, like, Dad's harmonica, you know", query: "dads")?.text == "\u{201C}um, it was, like, Dad's harmonica, you know\u{201D}")
    #expect(SearchSnippet.around("um, it was Dad's harmonica", query: "dads")?.parts.first(where: \.isMatch)?.text == "Dad's", "the mark covers the word as stored")
}
@Test func noMatchNoSnippet() {
    #expect(SearchSnippet.around("the lake", query: "harmonica") == nil)
    #expect(SearchSnippet.around("", query: "lake") == nil)
    #expect(SearchSnippet.around("the lake", query: "…") == nil)
}
@Test func aTitleMatchHasNoSecondLine() {
    #expect(SearchSnippet.line(for: titleHit, query: "drive") == nil)
}
@Test func aFactFoundInItsQuoteHasNoSecondLine() {
    #expect(SearchSnippet.line(for: factHit, query: "radios") == nil, "the heading already shows the words")
}
@Test func aFactFoundBeyondItsQuoteShowsTheWords() {
    // quote "I never could sit still"; telling "I never could sit still in Mrs Okafor's classroom"
    #expect(SearchSnippet.line(for: factBeyond, query: "classroom")?.parts.contains { $0.isMatch && $0.text == "classroom" } == true)
}
```

- [ ] **Step 2: Run `swift test --filter SearchSnippet`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Split the text on white space and keep each token as stored. A token matches when `SearchFold.fold(token)` starts with a query word. The window is 6 tokens before the first match and 7 after. A cut end gets "…". Trailing commas at a cut end are not removed: the words are as said.
- [ ] **Step 4: Run `swift test`.** Expected: PASS. Run the privacy grep.
- [ ] **Step 5: Commit** — `Kit: a search result shows the person's words around the match`

### Task 4: Store — the index in a fixed number of reads

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Store/SearchReads.swift` (an extension of `ExtractionStore`, as `PortraitReads.swift` is)
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/SearchReadsTests.swift`

**Interfaces:**
- Consumes: Task 2 `SearchIndex`; `EntityRepository.summaries(type:)` (visible entities only), `MemoryRepository.visibleMemories()`, `ProfileRepository.owner()`, `AppDatabase`, the `StatementCounter` pattern in `EntityBatchReadsTests.swift`.
- Produces:

```swift
extension ExtractionStore {
    /// What search may find (decision 6): every visible person, place, thing and idea but the owner, and every told,
    /// visible memory with the words of its tellings. A fixed number of statements, whatever the archive's size.
    public func searchIndex() throws -> SearchIndex
}
```

The reads: `summaries(type:)` for the four types; one statement for every alias (`alias` joined to `person` on `entity_id`); `visibleMemories()`; one statement for the words of every span, in order:

```sql
select ms.memory_id, ms."order", w.text
from memory_span ms
join memory m on m.id = ms.memory_id
join word w on w.segment_id = ms.segment_id and w.start_ms >= ms.start_ms and w.end_ms <= ms.end_ms
where m.hidden_from_timeline = 0 and m.created_from_candidate_id is not null
order by ms.memory_id, ms."order", w."index"
```

and one statement for the first telling's `session.started_at` of each memory. A continuation span (`continues_order` set) is its own entry in `tellings`.

- [ ] **Step 1: Write the failing tests**

Each test uses `ExtractionStore(try AppDatabase.inMemory())` and `StoreFixtures`. Invented people and words. A helper `tell(_:words:)` inserts a segment with `word` rows of 500 ms each, a candidate, and a kept memory whose span covers the given words.

```swift
@Test func theIndexHoldsWhatTheAppShows() throws {
    // Maya (alias "May"), a place, a thing, an idea, and the moment "The long drive" told with word rows
    let index = try store.searchIndex()
    #expect(Set(index.entities.map(\.summary.entity.title)) == ["Maya", "Alder Street", "Dad's Volvo", "Saying yes to things"])
    #expect(index.entities.first { $0.summary.entity.title == "Maya" }?.aliases == ["May"])
    #expect(index.memories.map(\.memory.title) == ["The long drive"])
    #expect(index.memories.first?.tellings == ["he kept an old harmonica in the glove box"])
    #expect(index.memories.first?.toldAt == session.startedAt)
}
@Test func aHiddenMemoryIsNotInTheIndex() throws {
    try store.memories.setHidden(drive.id, true)
    #expect(try store.searchIndex().memories.isEmpty)
    #expect(Search.run("harmonica", in: try store.searchIndex())?.isEmpty == true)
}
@Test func aHiddenEntityIsNotInTheIndex() throws {
    try store.entities.setHidden(maya.id, true)
    #expect(try store.searchIndex().entities.contains { $0.summary.entity.id == maya.id } == false)
}
@Test func aMemoryAndAnEntityKeptFromAIAreInTheIndex() throws {
    try store.memories.setExcluded(drive.id, true); try store.entities.setExcluded(maya.id, true)
    let index = try store.searchIndex()
    #expect(index.memories.count == 1 && index.entities.contains { $0.summary.entity.id == maya.id }, "decision 6")
}
@Test func aStandInAndTheOwnerAreNotInTheIndex() throws {
    _ = try store.memories.insertFloating(title: "Graduation", segment: segment.id, startMs: 0, endMs: 500)
    // the profile's owner is Jordan
    let index = try store.searchIndex()
    #expect(index.memories.map(\.memory.title) == ["The long drive"])
    #expect(index.entities.contains { $0.summary.entity.title == "Jordan" } == false)
}
@Test func wordsOutsideTheSpanAreNotInTheIndex() throws {
    // the segment says "um so anyway he kept an old harmonica"; trim the telling to "he kept an old harmonica"
    _ = try actions.trimTelling(drive.id, order: 0, startWord: 3, endWord: 7)
    #expect(try store.searchIndex().memories.first?.tellings == ["he kept an old harmonica"])
}
@Test func aSegmentWithNoKeptMemoryIsNotInTheIndex() throws {
    // a second segment "the accordion in the attic", status .pending, with a pending candidate and no memory
    #expect(Search.run("accordion", in: try store.searchIndex())?.isEmpty == true, "decision 18")
}
@Test func aSpanWithNoWordRowsAddsNothing() throws {
    // a memory kept on a segment inserted with words: []
    #expect(try store.searchIndex().memories.first { $0.memory.title == "The tree house" }?.tellings == [])
    #expect(Search.run("tree", in: try store.searchIndex())?.memories.count == 1, "the title still finds it")
}
@Test func aRetellingIsASecondTelling() throws {
    // mergeSpan adds a second span from another segment
    #expect(try store.searchIndex().memories.first?.tellings.count == 2)
}
@Test func aMergedEntityIsOneEntry() throws {
    // places "Ohio." and "Ohio"; merge the first into the second
    #expect(try store.entities.merge(ohioDot.id, into: ohio.id))
    #expect(try store.searchIndex().entities.filter { $0.summary.entity.type == .place }.map(\.summary.entity.title) == ["Ohio"])
}
@Test func aDeletedMemoryAndADeletedSessionLeaveTheIndex() throws {
    try store.memories.delete(drive.id)
    #expect(try store.searchIndex().memories.isEmpty)
    // second store: deleteSession removes its memories and their words
}
@Test func anEmptyArchiveGivesAnEmptyIndex() throws {
    #expect(try ExtractionStore(try AppDatabase.inMemory()).searchIndex() == .empty)
}
@Test func theIndexReadsInAFixedNumberOfStatements() throws {
    // Same counter as `summariesReadInAFixedNumberOfStatements`: read with 3 memories and 4 entities, add 30 of each, read again.
    #expect(statementsForMany == statementsForFew)
}
```

- [ ] **Step 2: Run `swift test --filter SearchReads`.** Expected: FAIL; `searchIndex` does not exist.
- [ ] **Step 3: Implement.** Join a telling's words with one space. Remove the owner by `profile.owner()?.entityID`. Drop `isFloating` memories. Do not read `segment.text`: it holds words outside the span.
- [ ] **Step 4: Run `swift test`.** Expected: PASS. Run the privacy grep.
- [ ] **Step 5: Commit** — `Store: the search index reads only what the app shows, in a fixed number of statements`

### Task 5: App — the search tab, names and the record bar

**Files:**
- Modify: `ios/Lifeline/Screens/Shell/AppTab.swift` (case `search`, `static let sections`), `ios/Lifeline/Screens/Shell/SectionsScreen.swift` (the search tab after the five)
- Create: `ios/Lifeline/Screens/Search/SearchViewModel.swift`, `ios/Lifeline/Screens/Search/SearchScreen.swift`, `ios/Lifeline/Screens/Search/SearchEntityRow.swift`
- Modify: `ios/Lifeline/Dependencies.swift` (one line: `-uiTesting-seedSearch`), `ios/Lifeline/UITestSeed.swift` (`writeSearch`, and an optional `words:` on `SeedSession.keep`)
- Modify: `ios/LifelineUITests/UITestHelpers.swift` (`launchWithSearch`, `openSearch`, `search(_:)`, `searchResult(_:)`)
- Test: create `ios/LifelineUITests/SearchUITests.swift`

**Interfaces:**
- Consumes: Task 2 `Search.run`, `SearchResults`; Task 4 `ExtractionStore.searchIndex()`; `PhotoRepository.covers(type:)`, `TileFace`, `EntityScreen`, `EntityViewModel`, `HomeViewModel.coverClosings`, `sectionHeadingStyle()`, `linenBackground()`.
- Produces:
  - `AppTab.search`, title "Search", symbol `magnifyingglass`, identifier `tab.search`. `AppTab.sections: [AppTab]` is the five sections in order; `SectionsScreen`'s `ForEach` uses it. After the `ForEach`: `Tab(value: AppTab.search, role: .search) { NavigationStack { SearchScreen(deps: deps) } }`. `home.tabChanged()` still runs on every tab change.
  - `@MainActor @Observable final class SearchViewModel`: `init(deps: Dependencies)` (no read); `var query: String` (each change runs the search); `private(set) var results: SearchResults?`; `private(set) var covers: [EntityID: Photo]`; `private(set) var isLoaded: Bool`; `private(set) var error: String?`; `func refresh()`. `refresh()` reads `searchIndex()` and `photos.covers(type: .person)` in a detached task, then sets the index on the main actor and runs the query again. A newer `refresh()` wins over an older one. The view model holds no matching rule: it calls `Search.run(query, in: index)`.
  - `SearchScreen(deps: Dependencies)`: owns the view model in `@State`. `.searchable(text: $viewModel.query, prompt: "Memories, people, places, things")` with `.autocorrectionDisabled()` and `.textInputAutocapitalization(.never)`. `.navigationTitle("Search")`. It calls `refresh()` on appear and when `home.coverClosings` changes while it is visible. States: not loaded or `results == nil`, the opening line (`search.prompt`); `error`, the error line (`search.error`); otherwise a `List` of sections in decision 11's order, each with a header (`search.heading`, `.accessibilityAddTraits(.isHeader)`). Task 5 draws the four entity groups. Task 6 adds "Memories" and "Nothing found".
  - `SearchEntityRow(hit: SearchResults.EntityHit, cover: Photo?, deps: Dependencies, onChange: () -> Void)`: a `NavigationLink` to `EntityScreen(viewModel: EntityViewModel(entity: hit.summary.entity, deps: deps), onChange: onChange)`. A person shows `TileFace` at 44 points, the title (headline, serif, `Theme.ink`) and `hit.secondLine` (footnote, `Theme.secondaryText`). A place, thing or idea shows the title only. `frame(minHeight: 44)` and `contentShape` are inside the label. One accessibility element: label the title, value `hit.secondLine ?? ""`. Identifier `search.result`. The face is hidden from accessibility, as on People.
  - `UITestSeed.writeSearch(store:profile:sessions:)`, under `-uiTesting-seedSearch`: the family from `people(…)`, then, all invented:
    - person "Zoë" (no moment); person "Lena" gets the alias "Linny";
    - thing "Dad's Volvo"; place "São Paulo";
    - moment "The long drive", 2004, with `word` rows for "we drove all night and he kept an old harmonica in the glove box";
    - moment "The red kite", range `.year(1998, origin: .inferred, evidence: nil)`;
    - moment "The attic stairs", hidden from the timeline, words "the accordion on the attic stairs";
    - moment "The quiet year", 2009, kept from AI;
    - fact, stored title "Took things apart", quote "I was always the kid who dismantled radios".
  - `XCUIApplication.launchWithSearch(_ extra: [String] = [])`; `openSearch()` taps the search tab (`tabBars.buttons["Search"]`); `search(_ text: String)` opens the tab, taps the search field and types; `searchResult(_ label: String)` is the `search.result` button with that label.

- [ ] **Step 1: Create the simulator for this worktree.** `xcrun simctl create "Lifeline Search" "iPhone 17 Pro"`. Use its id in every `-destination`.
- [ ] **Step 2: Write the failing UI tests**

```swift
final class SearchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSearchIsATabBesideTheFive() {
        let app = XCUIApplication.launchWithSearch()
        for title in ["Timeline", "People", "Places", "Things", "You", "Search"] {
            XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 5), "a tab titled \(title)")
        }
    }
    @MainActor
    func testTheEmptyFieldShowsOneLineAndNoResults() {
        let app = XCUIApplication.launchWithSearch(); app.openSearch()
        XCTAssertTrue(app.staticTexts["search.prompt"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["search.prompt"].label, "Search by a name, or by words you said.")
        XCTAssertEqual(app.searchFields.firstMatch.placeholderValue, "Memories, people, places, things")
        XCTAssertFalse(app.buttons["search.result"].exists)
        XCTAssertFalse(app.staticTexts["search.none"].exists, "an empty field is not a failed search")
    }
    @MainActor
    func testANameFindsThePersonAndOpensTheirPage() {
        let app = XCUIApplication.launchWithSearch(); app.search("maya")
        let maya = app.searchResult("Maya")
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        XCTAssertEqual(maya.value as? String, "my sister")
        maya.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Maya")
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story about Maya", "the bar names the page (decision 16)")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5), "back returns to the results")
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "maya")
    }
    @MainActor
    func testCaseDiacriticsAndApostrophesDoNotMatter() {
        let app = XCUIApplication.launchWithSearch(); app.search("ZOE")
        XCTAssertTrue(app.searchResult("Zoë").waitForExistence(timeout: 5))
        app.clearSearch(); app.search("dads volvo")
        XCTAssertTrue(app.searchResult("Dad's Volvo").waitForExistence(timeout: 5))
    }
    @MainActor
    func testAnAliasFindsThePersonAndShowsTheAlias() {
        let app = XCUIApplication.launchWithSearch(); app.search("linny")
        XCTAssertEqual(app.searchResult("Lena").value as? String, "Linny")
    }
    @MainActor
    func testResultsGroupByKindInOrder() {
        let app = XCUIApplication.launchWithSearch(); app.search("dad")
        XCTAssertTrue(app.searchResult("Dad").waitForExistence(timeout: 5))
        let headings = app.staticTexts.matching(identifier: "search.heading").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Array(headings.prefix(2)), ["People", "Things"], "a group with no result does not show")
        XCTAssertLessThan(app.searchResult("Dad").frame.minY, app.searchResult("Dad's Volvo").frame.minY)
    }
    @MainActor
    func testTheOwnerIsNotAResult() {
        let app = XCUIApplication.launchWithSearch(); app.search("jordan")
        XCTAssertFalse(app.searchResult("Jordan").waitForExistence(timeout: 3))
    }
    @MainActor
    func testTheBarStartsAStoryFromSearchAndTheQueryStays() {
        let app = XCUIApplication.launchWithSearch(); app.search("maya")
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5))
        app.dismissSearchKeyboard()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 5))
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story")
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
        app.finishSession()
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 10), "the results are read again under the same query")
    }
    @MainActor
    func testTheQueryIsGoneAfterARelaunch() {
        let app = XCUIApplication.launchWithSearch(["-uiTesting-db", NSTemporaryDirectory() + "search-relaunch-\(UUID().uuidString)"]); app.search("maya")
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.openSearch()
        XCTAssertTrue(app.staticTexts["search.prompt"].waitForExistence(timeout: 10), "nothing typed is kept (decision 19)")
    }
    @MainActor
    func testANameRowIsFullSizeAtTheLargestText() {
        let app = XCUIApplication.launchWithSearch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.search("maya")
        let maya = app.searchResult("Maya")
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(maya.frame.height, 44)
        XCTAssertEqual(maya.value as? String, "my sister", "the own words still read")
    }
}
```

`clearSearch()` and `dismissSearchKeyboard()` are helpers in `UITestHelpers.swift`. The seed under `-uiTesting-db` must not write twice: `writeSearch` returns at once when the profile already has an owner.

- [ ] **Step 3: Run `-only-testing:LifelineUITests/SearchUITests`.** Expected: FAIL; there is no search tab.
- [ ] **Step 4: Build the tab, the view model, the screen and the row as the Interfaces block says.** Run `xcodegen generate` after adding files. Use the system search tab and field; draw no custom field. Then check in the simulator, and record in the task report, each of these: where the field shows; whether the record bar shows on the search tab with the field idle, with the field active, and with the keyboard up; whether the tab bar and the bar return when the keyboard goes. If the bar does not show on the search tab with the field idle, stop and ask the owner (see "Limits").
- [ ] **Step 5: Run `swift test`, then `-only-testing:LifelineUITests/SearchUITests -only-testing:LifelineUITests/ShellUITests -only-testing:LifelineUITests/PeopleUITests`.** Expected: PASS. Run the privacy grep on the new app files.
- [ ] **Step 6: Commit** — `Search: a search tab finds people, places, things and ideas by name` (body: P9 for the opening state; decision 19 for no history)

### Task 6: App — memories, the words around a match, and nothing found

**Files:**
- Create: `ios/Lifeline/Screens/Search/SearchMemoryRow.swift`, `ios/Lifeline/Screens/Search/SnippetText.swift`
- Modify: `ios/Lifeline/Screens/Search/SearchScreen.swift` (the "Memories" group, the "Nothing found" state, the announcement)
- Test: `ios/LifelineUITests/SearchUITests.swift`

**Interfaces:**
- Consumes: Task 2 `SearchResults.MemoryHit`; Task 3 `SearchSnippet.line(for:query:)`; `MemoryScreen`, `MemoryViewModel`.
- Produces:
  - `SnippetText(snippet: SearchSnippet)`: one `Text` built from the parts; a matched part is `.fontWeight(.semibold)` in `Theme.ink`; the rest is `Theme.secondaryText`; footnote style. No colour marks the match.
  - `SearchMemoryRow(hit:query:deps:onChange:)`: a `NavigationLink` to `MemoryScreen(viewModel: MemoryViewModel(memory: hit.memory, deps: deps), deps: deps, onChange: onChange)`. Lines: `hit.heading` (headline, serif, `Theme.ink`); `hit.dateText` when not nil (footnote, semibold, `Theme.ochreText`); the snippet when `SearchSnippet.line` is not nil. One accessibility element: label `hit.heading`; value the date text and the snippet's text, joined with ". ". Identifier `search.result`. `frame(minHeight: 44)` inside the label.
  - `SearchScreen`: the "Memories" section after the entity groups. When `results?.isEmpty == true`: the title "Nothing found" (`search.none`, headline) and the line "Search looks at names and at the words of memories you kept." (footnote, `Theme.secondaryText`), with no button. When the state becomes "nothing found", post `AccessibilityNotification.Announcement("Nothing found")` once for that query. Each row's `onChange` calls `viewModel.refresh()`.

- [ ] **Step 1: Write the failing UI tests**

```swift
@MainActor
func testWordsYouSaidFindTheMemoryAndShowThem() {
    let app = XCUIApplication.launchWithSearch(); app.search("harmonica")
    let drive = app.searchResult("The long drive")
    XCTAssertTrue(drive.waitForExistence(timeout: 5))
    XCTAssertEqual(drive.value as? String, "2004. \u{201C}…night and he kept an old harmonica in the glove box\u{201D}")
    XCTAssertEqual(app.staticTexts.matching(identifier: "search.heading").allElementsBoundByIndex.map(\.label), ["Memories"])
    drive.tap()
    XCTAssertTrue(app.any("memory.range").waitForExistence(timeout: 5), "the memory page is up")
    XCTAssertEqual(app.buttons["home.start"].label, "Tell a story")
}
@MainActor
func testATitleMatchShowsNoSnippet() {
    let app = XCUIApplication.launchWithSearch(); app.search("long drive")
    XCTAssertEqual(app.searchResult("The long drive").value as? String, "2004")
}
@MainActor
func testAGuessedDateReadsAsAGuess() {
    let app = XCUIApplication.launchWithSearch(); app.search("kite")
    XCTAssertEqual(app.searchResult("The red kite").value as? String, "around 1998")
}
@MainActor
func testAFactShowsItsWordsAsTheHeading() {
    let app = XCUIApplication.launchWithSearch(); app.search("radios")
    XCTAssertTrue(app.searchResult("\u{201C}I was always the kid who dismantled radios\u{201D}").waitForExistence(timeout: 5))
    app.clearSearch(); app.search("took")
    XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5), "a title no screen shows finds nothing (decision 3)")
}
@MainActor
func testAHiddenMemoryIsNotFound() {
    let app = XCUIApplication.launchWithSearch(); app.search("accordion")
    XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5))
    app.clearSearch(); app.search("attic")
    XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5), "not by its title either")
}
@MainActor
func testAMemoryKeptFromAIIsFound() {
    let app = XCUIApplication.launchWithSearch(); app.search("quiet year")
    XCTAssertTrue(app.searchResult("The quiet year").waitForExistence(timeout: 5), "decision 6")
}
@MainActor
func testNothingFoundSaysWhatSearchLooksAt() {
    let app = XCUIApplication.launchWithSearch(); app.search("xylophone")
    XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["search.none"].label, "Nothing found")
    XCTAssertTrue(app.staticTexts["Search looks at names and at the words of memories you kept."].exists)
    XCTAssertFalse(app.buttons["search.result"].exists)
}
@MainActor
func testPunctuationAloneIsNotASearch() {
    let app = XCUIApplication.launchWithSearch(); app.search("…!")
    XCTAssertTrue(app.staticTexts["search.prompt"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["search.none"].exists)
}
@MainActor
func testARenameShowsOnReturn() {
    let app = XCUIApplication.launchWithSearch(); app.search("volvo")
    app.searchResult("Dad's Volvo").tap()
    app.renameEntity(to: "The green Volvo")            // entity.more, entity.rename, as EntityPageUITests does
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.searchResult("The green Volvo").waitForExistence(timeout: 5))
    XCTAssertFalse(app.searchResult("Dad's Volvo").exists)
}
@MainActor
func testADeletedMemoryLeavesTheResults() {
    // Hide is the change a memory page offers; Delete lives on the Timeline row.
    let app = XCUIApplication.launchWithSearch(); app.search("harmonica")
    XCTAssertTrue(app.searchResult("The long drive").waitForExistence(timeout: 5))
    app.openTab("Timeline"); app.deleteTimelineMemory("The long drive")   // row.more, row.delete, row.confirmDelete
    app.openSearch()
    XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5), "the tab reads again when it appears; the query is kept")
}
@MainActor
func testAMemoryRowReadsInFullAtTheLargestText() {
    let app = XCUIApplication.launchWithSearch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.search("harmonica")
    let drive = app.searchResult("The long drive")
    XCTAssertTrue(drive.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(drive.frame.height, 44)
    XCTAssertTrue((drive.value as? String)?.contains("harmonica") == true)
    XCTAssertLessThanOrEqual(drive.frame.maxX, app.windows.firstMatch.frame.maxX, "nothing runs off the edge")
}
```

`renameEntity(to:)` and `deleteTimelineMemory(_:)` are helpers in `UITestHelpers.swift`, built from the steps `EntityPageUITests` and `YouUITests` already use.

- [ ] **Step 2: Run `-only-testing:LifelineUITests/SearchUITests`.** Expected: FAIL; no memory is a result.
- [ ] **Step 3: Implement as the Interfaces block says.**
- [ ] **Step 4: Run `swift test`, then `-only-testing:LifelineUITests/SearchUITests -only-testing:LifelineUITests/ShellUITests -only-testing:LifelineUITests/EntityPageUITests -only-testing:LifelineUITests/TimelineUITests`.** Expected: PASS. Run the privacy grep on the new app files.
- [ ] **Step 5: Commit** — `Search: memories by their title or the words you said, with the words around the match` (body: P1 for words as said, P5 for the date line, P8 for hidden rows)

### Task 7: Docs, screenshots and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` ("The shape of the app" paragraph; "Designed, not built" if search is listed there)
- Modify: `docs/DECISIONS.md` (one entry for S5, dated the day it is written: decisions 1, 3, 4, 6, 7, 11, 18, 19 and 21, each with its cost)
- Create: `docs/plans/2026-11-16-sections-search-device-check.md`
- Create: `docs/screenshots/sections-search/before-tabs.png`, `after-opening.png`, `after-names.png`, `after-memories.png`, `after-nothing-found.png`, `after-page-from-search.png`, `after-largest-text.png`

- [ ] **Step 1: Take the screenshots.** Before: `origin/main` in a temporary worktree (`git worktree add ../lifeline-search-before origin/main`), the Timeline with `-uiTesting -uiTesting-seedPeople`, to show the tab bar with no search. After: this branch with `-uiTesting -uiTesting-seedSearch`: the opening state; "dad" (two groups); "harmonica" (a memory with its words); "xylophone" (nothing found); Maya's page opened from a result, with the bar; "harmonica" at `UICTContentSizeCategoryAccessibilityXXXL`. Use an uncommitted `ScreenshotTour.swift` in the UI test target that keeps each screen as an `XCTAttachment`, run it with `-resultBundlePath`, and export with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`. Remove the temporary worktree and delete `ScreenshotTour.swift`.
- [ ] **Step 2: Update OVERVIEW.** Say that search is the trailing tab; what it looks at (names, aliases, moment titles, the words of kept memories); what it does not (hidden rows, words in no kept memory); that results group by kind; that nothing typed is kept or sent.
- [ ] **Step 3: Add the DECISIONS entry** in the file's format, newest first, with the costs: the scan reads every kept word when the tab appears (decision 1); aliases are searched and a fact's stored title is not (decision 3); a memory kept from AI is found (decision 6); no spelling tolerance (decision 7); a story still being sorted is not found (decision 18); no recent searches (decision 19).
- [ ] **Step 4: Write the device checklist.** Each item is one line the owner ticks on the iPhone:
  1. The search tab shows beside the five tabs in light and dark appearance, and with Reduce Transparency on.
  2. The record bar shows on the search tab; it reads "Tell a story"; it names the page after a result is opened.
  3. With the keyboard up, the results scroll clear of the keyboard and the last row can be reached.
  4. Type a name the phone tends to "correct"; the field does not change it.
  5. Type a word you said in a memory you kept; the row shows your words around it, with the word in heavier type.
  6. Hide a memory, then search for its title; it is not found. Show it again; it is found.
  7. On the full archive, the first results show without a visible wait after the tab opens, and typing does not stutter.
  8. With VoiceOver: each result reads as one button with its second line as the value; the rotor's Headings move between "People", "Places", "Things", "What you think" and "Memories"; "Nothing found" is spoken once.
  9. At the largest accessibility text size, every row reads in full and nothing is cut.
  10. In Airplane Mode, search works as before.
  11. Force-quit the app and open it again; the search field is empty.
- [ ] **Step 5: Run `swift test`.** Expected: PASS. Do not run the whole UI suite here; the controller runs it after the final review.
- [ ] **Step 6: Run the privacy grep over `ios/Lifeline/Screens/Search` and the four new kit files.** Expected: no output. Check that `git status` shows no `ios/Config/Local.xcconfig` and no `ScreenshotTour.swift`.
- [ ] **Step 7: Commit** — `Docs: search in the overview, screenshots, and the device checklist`

---

## After S5

- **Owner's calls from use.** Whether "Memories" must show above the names. Whether the search tab needs "Show hidden". Whether a result must show who and where.
- **Words in no kept memory.** Search over session transcripts needs a spec section: a result would open the session, not a memory, and a dismissed card's words would be found.
- **Stories, chapters and tags.** S6c gives a chapter a sheet. A story or a chapter title can be a result once it has a page to open.
- **Scale.** If device checklist item 7 fails on a large archive, cache the index between appearances and rebuild it on `coverClosings`, or move to FTS5 behind `Search.run` with its own migration and a delete that purges the index.
- S7 (Things) and S8 (Places) change the Things and Places tabs. A search result opens `EntityScreen` and does not depend on either.
- The dark and increased-contrast colour values still have no PR assigned.
