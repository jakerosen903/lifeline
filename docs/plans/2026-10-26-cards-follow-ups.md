# Cards: Follow-ups on the Memory Card — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hint, entity or person follow-up never shows as its own card; after Keep the memory card stays as a "Kept" card with one chip per follow-up. Also fix the two `EntitiesUITests` that fail on `main`.

**Architecture:** Ownership (which memory a follow-up belongs to) and chip text are pure LifelineKit code. `Card` gains a `.kept(KeptCard)` case; `CardQueue` holds follow-ups under their owner memory and swaps a kept memory card for a `.kept` card in the same position, so order and identity (the memory candidate id) are kept. `CardQueue.closeKept` returns what the app must dismiss and what must become an open mention; the app runs those through `CardHandler`. The session, session detail and timeline screens render `.kept` through a new `KeptCard` view.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XCUITest.

**Spec:** `docs/specs/2026-10-26-cards-follow-ups.md`

## Global Constraints

- Branch `cards-b` in worktree `scratchpad/wt-cards`. Nothing is pushed by the executor.
- Kit tests: `cd ios/LifelineKit && swift test`. App build: `xcodebuild build -project ios/Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE'`. UI tests: `xcodebuild test -project ios/Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`. Run `xcodegen generate` in `ios/` after adding app or UI-test files. Only one `xcodebuild test` may run on the simulator at a time.
- Commits: `git -c user.name="Jake Rosen" -c user.email=jakerosen27@gmail.com commit`, imperative one-line message, trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Fixtures are invented. Never use a real person's data.
- Identifiers: `card.kept`, `card.followUp`, `card.keptDone`. Auto-close delay after the last chip is answered: 1.5 s.
- Chip text, exactly: domain "Family?" (first letter capitalized); story "Story: {phrase}?"; collection "Collection: {phrase}?"; chapter "Chapter: {phrase}?"; thing "{text}: a thing?"; place "{text}: a place?"; idea "{title ?? text}: something you think?"; person "{text}: who's this?". Checked: "✓ " + the text without the trailing "?" and without the type suffix for entities and people ("✓ Family", "✓ Story: the steak dinner", "✓ the shed", "✓ Theo").
- Code style: match the surrounding code (doc comments on types and non-obvious funcs, one responsibility per file).

## Review Focus

1. A follow-up arriving in a later extraction event than its memory (after Keep): must join the open kept card or make a new kept card, never a standalone card.
2. Dismiss then Undo on a memory card: its follow-ups must come back held, not lost (today hints are dropped on dismiss).
3. A heavy moment mid-session: Keep must not show chips; follow-ups stay pending in the store.
4. Keep on memory B while A's kept card is open: A closes first and its unanswered follow-ups are dismissed or opened as mentions exactly once.
5. App killed after Keep, before answering: session detail and the timeline must show one kept card for the memory, not separate follow-up cards.

---

### Task 1: The two failing EntitiesUITests

**Files:** found by diagnosis; likely `ios/Lifeline/Screens/Entities/*`, `ios/LifelineUITests/EntitiesUITests.swift`.

- [ ] **Step 1:** Run `-only-testing:LifelineUITests/EntitiesUITests` on this branch. Expected: `testEntityPagesShowDetailsAboveMomentsAndIdeasInOrder` fails (1 idea moment, expected 2) and `testThingsFilterByDomainTag` fails (no `entities.tagFilter`).
- [ ] **Step 2:** Find the cause of each (superpowers:systematic-debugging). Check `git log -p` on the entity screens and the tests from PR #11's last review round. Write the cause in the report.
- [ ] **Step 3:** Fix the app when the app is wrong; fix the test when the test is out of date (say why in the commit body). Do not change the cards flow in this task.
- [ ] **Step 4:** Run `EntitiesUITests`. Expected: 3/3 pass.
- [ ] **Step 5:** Commit.

### Task 2: Ownership and chip text (LifelineKit)

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Extraction/FollowUpOwner.swift`, `ios/LifelineKit/Sources/LifelineKit/Extraction/FollowUpLabel.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/FollowUpOwnerTests.swift`, `FollowUpLabelTests.swift` (match the tests folder's layout)

**Interfaces:**
- Produces: `Card.isFollowUp: Bool` (true for `.hint`, `.entity`, `.whoIsThis(.candidate, _)`; false for `.memory`, `.whoIsThis(.mention, _)`, `.kept`). Add `.kept` only in Task 3; until then the switch covers the existing cases.
- Produces: `public enum FollowUpOwner { public static func owner(of followUp: Card, among memories: [(Candidate, MemoryOut)], excluding: Set<String>) -> String? }` — returns the owning memory candidate id per spec "Which memory owns a follow-up" rules 1–5. `memories` may come in any order; "first" is lowest `ordinal`; only memories with the follow-up candidate's `segmentID` count (hints use `memoryCandidateID` directly and still respect `excluding`, returning nil when their memory is excluded). `excluding` holds dismissed memory candidate ids.
- Produces: `public enum FollowUpLabel { public static func question(_ followUp: Card) -> String; public static func done(_ followUp: Card) -> String }` — exact text from Global Constraints.

- [ ] **Step 1: Write the failing tests.** Owner tests: `hintOwnedByItsMemoryID`, `hintWithExcludedMemoryHasNoOwner`, `entityOwnedByAboutRef`, `entityOwnedByEntityRefTextAndKind` (normalized text "The Shed" vs "the shed"; a ref of a different kind does not match), `placeOwnedByPlaceText`, `personOwnedByPeopleRefs`, `personOwnedByAboutRef`, `firstByOrdinalWins`, `excludedMemoryPassesToNext`, `otherSegmentDoesNotOwn`, `noReferenceMeansNoOwner`. Label tests: one per row of the chip table, plus `done` for domain, story, thing and person.
- [ ] **Step 2:** `swift test --filter "FollowUpOwner|FollowUpLabel"` — Expected: FAIL (types missing).
- [ ] **Step 3:** Implement. Use `PeopleRepository.normalize` for text; `MemoryOut.entityRefs` plus the place from `placeText` (there is an existing helper near `ExtractorOutput.swift:125` that appends the place; reuse it). Read `MentionOut.kind` → entity type via the existing `entityType` mapping.
- [ ] **Step 4:** `swift test` — Expected: green.
- [ ] **Step 5:** Commit.

### Task 3: The queue holds follow-ups and makes kept cards (LifelineKit)

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Extraction/CardQueue.swift`
- Create: `ios/LifelineKit/Sources/LifelineKit/Extraction/KeptCard.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/CardQueueTests.swift` (extend; keep existing tests passing or update the ones the spec changes, and list each changed test in the report)

**Interfaces:**
- Consumes: `FollowUpOwner.owner`, `Card.isFollowUp` (Task 2).
- Produces:
  - `public struct KeptCard: Equatable, Sendable { public var memoryCandidateID: String; public var title: String; public var followUps: [Card]; public var answered: Set<String>; public var isComplete: Bool { get } }`
  - `Card.kept(KeptCard)`, with `id` = `memoryCandidateID`. Update every exhaustive `switch` on `Card` in the kit.
  - `public struct KeptClose: Equatable, Sendable { public var dismiss: [Card]; public var openAsMention: [Card] }` — unanswered hint/entity follow-ups go to `dismiss`; unanswered `.whoIsThis(.candidate)` go to `openAsMention`.
  - `CardQueue`: `mutating func memoryAccepted(_ id: String)` (now: swap the memory card for `.kept` in place when it has held follow-ups and the queue is not suppressed; else remove it), `mutating func memoryDismissed(_ id: String)` (remove the card; its follow-ups re-own to the next memory or stay hidden; never dropped), `mutating func restore(_ card: Card)` (unchanged contract; a restored memory takes its follow-ups back), `mutating func answered(_ followUpID: String, in memoryID: String) -> Bool` (returns `isComplete`), `mutating func closeKept(_ memoryID: String) -> KeptClose`, `mutating func closeAllKept() -> KeptClose`.
  - `apply(_:)`: memory cards append as now; follow-ups never append. A follow-up whose owner is already accepted joins that memory's open `.kept` card, or appends a new `.kept` card (title from the remembered `MemoryOut`) when none is open. Follow-ups with no owner are kept and re-checked on later events.
  - Replace `waitingCards` with `public static func waiting(pending: [Candidate], segmentMemories: (SegmentID) -> [Candidate], statusOf: (CandidateID) -> CandidateStatus?) -> [Card]`: pending memory cards appear as `.memory` with their pending follow-ups held (expose them via a second static, or return a `CardQueue` value — implementer's choice, state it in the report); pending follow-ups whose owner memory is `.accepted` group into one `.kept` card per memory, in the order of their first follow-up; follow-ups whose owner is dismissed or missing do not appear.
  - Remove `heldHintCount` if nothing outside tests reads it; otherwise rename to `heldFollowUpCount`.
- [ ] **Step 1: Write the failing tests:** `followUpsNeverBecomeCards`, `keepWithFollowUpsLeavesAKeptCardInPlace` (position and id preserved), `keepWithoutFollowUpsRemovesTheCard`, `dismissHidesFollowUpsAndUndoRestoresThem`, `dismissPassesEntityToNextMemory`, `answeredReportsCompletion`, `closeKeptSortsDismissAndMention`, `closeAllKeptClosesEveryOpenCard`, `lateFollowUpJoinsOpenKeptCard`, `lateFollowUpAfterCloseMakesNewKeptCard`, `suppressedKeepShowsNoChips`, `continuationKeepsHeldFollowUps`, `waitingGroupsFollowUpsUnderAcceptedMemory`, `waitingDropsFollowUpsOfDismissedMemory`.
- [ ] **Step 2:** `swift test --filter CardQueue` — Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` — Expected: green. The app will not build until Task 4; that is expected.
- [ ] **Step 5:** Commit.

### Task 4: Kept card in the live session (app)

**Files:**
- Create: `ios/Lifeline/Screens/Cards/KeptCard.swift` (view `KeptCardView`), `ios/Lifeline/Screens/Cards/FollowUpChip.swift`
- Modify: `CardStack.swift`, `CardHandler.swift`, `Session/SessionViewModel.swift`, `Session/SessionScreen.swift`
- Delete: `HintCard.swift`, `EntityCard.swift` when unused after Task 5 (delete in Task 5 if the timeline still needs them here).

**Interfaces:**
- Consumes: Task 3's `CardQueue` API, `FollowUpLabel`.
- Produces:
  - `CardHandler.acceptFollowUp(_ card: Card, as type: EntityType?) -> Bool` (hint → `acceptHint`; entity → `acceptEntity`; never navigates), `CardHandler.close(_ closing: KeptClose)` (dismisses without the undo notice; opens mentions via the existing `acceptMention` path in `shown`).
  - `CardStack` new parameters: `onFollowUp: (KeptCard, Card, EntityType?) -> Void`, `onResolveFollowUp: (KeptCard, Card, MentionChoice) -> Void`, `onKeptDone: (KeptCard) -> Void`, `onOpenEntity: ((Card) -> Void)?` (nil in the live session).
  - `SessionViewModel`: every memory action (`accept`, `change`, `dismiss`, `sameStory`) first runs `cards.close(cardQueue.closeAllKept())`. New `followUp(_:_:as:)`, `resolveFollowUp(_:_:_:)`, `keptDone(_:)`; when `answered` returns true, close that kept card after 1.5 s unless the person already did.
- [ ] **Step 1:** Build the views. `KeptCardView`: checkmark + "Kept", the title on one line, a `FlowLayout` of `FollowUpChip`s, "Done". Same card chrome as `MemoryCard` (`Theme.sand`, radius 18, padding 16). A chip is a capsule button (`Theme.linen` fill, olive text when open, stone with checkmark when done). Entity chips get a `.contextMenu` with the other types and "Not any of these" (reuse `EntityCard`'s label list). A person chip presents a sheet with `WhoIsThisCard`'s choices.
- [ ] **Step 2:** Wire `CardStack` (`.kept` case in `cardView`) and `SessionViewModel`/`SessionScreen`.
- [ ] **Step 3:** App build — Expected: BUILD SUCCEEDED (fix the other `CardStack` callers minimally so the app builds; Task 5 finishes them).
- [ ] **Step 4:** Commit.

### Task 5: Session detail, timeline and People

**Files:** `SessionDetail/SessionDetailViewModel.swift`, `SessionDetail/SessionDetailScreen.swift`, `Timeline/TimelineViewModel.swift`, `Timeline/TimelineScreen.swift`, `People/PeopleScreen.swift` (only to compile), the store method that lists a segment's memory candidates (add one to the candidate repository if none exists, with a kit test).

- [ ] **Step 1:** Switch both waiting lists to `CardQueue.waiting(...)`. Keep, dismiss and the chips behave as in the session (spec "Session detail and the timeline"). A checked entity or person chip opens that entity's page via the screen's existing navigation (spec rule 8).
- [ ] **Step 2:** Delete `HintCard.swift` and `EntityCard.swift` if unused; `xcodegen generate`.
- [ ] **Step 3:** `swift test` and app build — Expected: green; BUILD SUCCEEDED.
- [ ] **Step 4:** Commit.

### Task 6: UI tests

**Files:** Create `ios/LifelineUITests/FollowUpUITests.swift`; modify `EntitiesUITests.swift`, `LandingUITests.swift`, and the fixture extractor output the UI tests use (find it via the `card.hintYes` / `card.entityKeep` users).

- [ ] **Step 1:** Write `FollowUpUITests`: `testKeepShowsChipsOnTheSameCard` (after Keep, `card.kept` exists, holds the memory's title, and no `card.hint`/`card.entity` element exists), `testDomainChipChecks` ("Family?" → "✓ Family"), `testThingChipStaysOnSession` (no `entity.title` appears), `testDoneClosesTheKeptCard`, `testPersonChipOpensWhoIsThis`. Add fixture output for a memory with a domain hint, a thing and a person, all invented.
- [ ] **Step 2:** Move `EntitiesUITests` and `LandingUITests` off `card.entityKeep` / `card.hintYes` to the chips. `testThingsFilterByDomainTag` keeps the thing via its chip, then opens Things from the timeline.
- [ ] **Step 3:** Run the full UI suite (`-only-testing:LifelineUITests`). Expected: all pass. Report the count.
- [ ] **Step 4:** Commit.
