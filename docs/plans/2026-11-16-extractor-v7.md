# A2: Extractor v7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app knows who is speaking, links a fact or feeling to who it is about, shows a fact, feeling or goal as the person's quote with no made-up title, treats "our parents" as more than one person, and stops storing one place twice.

**Architecture:** Three PRs. A2a is kit rules with no prompt change: each rule is a pure function or a repository change with tests, so it is safe to merge while v6 still runs. A2b is the prompt, the schema value, the packet field, the test transcripts and the v6 against v7 comparison; it changes what the model is asked. A2c is the app: the cards, the person's page, and the Change sheet.

**Tech Stack:** Swift 6, Swift Testing, XCUITest, GRDB 7. No migration (decision 1). No new network host.

**Spec:** `docs/specs/2026-11-16-audit-data-fixes.md`, every "A2" section, "Principles" and "Owner's calls". `docs/DECISIONS.md`, entries of 2026-11-16 "Owner's calls on the audit data fixes" and "A feeling has no title, and “our parents” is not one person". A1 merged in #23 and gives this plan `MatchKey`, `StoryRepository.merge` and `ArchiveRepair`.

**Branches:** `v7-rules` (A2a), `v7-prompt` (A2b, on A2a), `v7-app` (A2c, on A2b). Each from `origin/main` once the one before it merges.

---

## Decisions made in this plan

The spec leaves these open. Each one is decided here so the owner can overrule it before work starts.

1. **No stored match-key column, so no migration.** The spec asked for a column on `entity`, `story`, `chapter` and `collection`. Those tables hold tens to hundreds of rows. A lookup reads the rows of one type and compares keys in Swift, as the story lookup in #23 does. This removes A2's only migration. A2 then does not wait for Photos, and it cannot collide with Photos' v13. The spec's "Data" section is changed to match.
2. **Entities with one key are merged by the launch repair,** as stories are (owner's call 1). The merge moves every link of the entity that goes to the one that stays. The entity made first stays.
3. **People are never merged by the repair.** Two people can share a name. Only places, things and collections are joined by key. Ideas match by id only, as today.
4. **v7 becomes the default in A2b's last task,** after the owner reads the comparison. Until that commit, `ExtractorConfig.version` stays "v6" and every A2a rule runs on v6 output.
5. **The group list in code is short and in English.** It catches the plural kin words in the spec. The prompt carries the general rule; the code list is the safety net for the common cases.
6. **"That's me" needs an owner.** With no owner row, the button does not show.
7. **A2c is three small PRs if the session prefers:** cards, the person's page, the Change sheet. They touch different files.

### Limits found while planning

- **No score exists for prompt quality.** The only measure is the comparison in A2b, read by the owner. It needs an Anthropic key and runs on the Mac, not in CI.
- **The repair is not wired into the app yet.** #23 left that for a Mac session (`docs/plans/2026-11-16-story-fix.md`, "Not in this PR"). A2a adds the entity merge to the same repair. The wiring task is A2c Task 1 unless it is done sooner.
- **Photos adds `photo_link.entity_id`.** If Photos has merged when A2a is built, the entity merge must move photo links too. Task 3 says how.

---

## Global Constraints

- No migration in any A2 PR. `MigrationsTests` does not change.
- Rules 1 to 4 of `extractor.v6.md` (only what is said, summaries, confidence, disclosure) are copied to v7 word for word. A test compares them. No A2 change touches `Arc/FixedResponses/` or how a disclosure is answered.
- The code never trusts the prompt for a rule the spec gives to both. Each such rule has a pure function and a test that needs no network.
- Nothing is linked, merged or renamed that the person did not say or tap, except the two repairs the owner approved (stories and entities with one key).
- Stored spelling never changes. Only comparisons use the key.
- The decoder stays tolerant of v1 to v6 payloads. A candidate stored by an older version must still decode.
- Copy, exact:
  - Card: "That's me". Group chip: "Who are “{phrase}”?". Group list: "Leave it as said".
  - Person's page: heading "Other names", action "Remove".
  - Change sheet for a fact, feeling or goal: "About whom or what?", "What kind", "Who it mentions", "Said before".
  - Repair notice for entities: "Joined 2 copies of “Ohio”." With stories and entities both: "Joined copies of {n} things that had the same name."
- Kit tests: `cd ios/LifelineKit && swift test`. UI test scope (owner, 2026-11-15): a task runs only the UI classes it names; the whole suite runs once at the end of A2c.
- No test's assertion is weakened. A test that asserts behaviour this plan changes moves to the new behaviour with an assertion of equal strength, and the task names it.
- Fixtures are invented; never a real person's words.

## Review Focus

1. **The owner is never a person mention.** By the prompt, by the code filter, and by the lookup. A2a Task 4, A2b Task 2.
2. **A group phrase is never saved as a name.** A2a Task 6, A2c Task 3.
3. **An entity merge loses nothing.** Every table that names an entity is covered, in one transaction. A2a Task 3.
4. **Disclosure rules are unchanged.** A2b Task 1.
5. **Old payloads decode.** A2b Task 3.

---

## A2a — the kit rules (`v7-rules`)

Kit only. CI can check all of it. No screen changes.

### Task 1: The match key replaces `normalize` for names

- Modify: `Store/EntityRepository.swift` (`find(type:title:)`, `insert`), `Store/ChapterRepository.swift` (`insertCollection`), `Confirmation/CandidateActions.swift` (the chapter-hint title match at "acceptHint"), `Extraction/ExtractionQueue.swift` (`entityOnFile`).
- Each lookup reads the rows of one type and returns the first, in creation order, whose `MatchKey.of(title)` equals the key. An empty key finds nothing.
- `PeopleRepository.normalize` stays for people and aliases. People are out of scope here (decision 3).
- Tests: `EntityMatchKeyTests`: "Ohio." finds "Ohio"; "ohio" finds "Ohio"; "St. Louis" does not find "St Louis"; a place and a thing with one title stay two; an idea is not found by title; an empty title finds nothing. Add one case each to `ChapterRepositoryTests` (collection) and `HintActionsTests` (chapter hint "childhood." reuses "Childhood").
- [ ] Tests first, FAIL. Implement. `swift test` PASS. **Commit** — `Kit: places, things, chapters and collections match by key`

### Task 2: A generic place makes no entity

- Create: `Domain/GenericPhrase.swift`: `static func isGeneric(_ text: String) -> Bool`, true when the first word is "a", "an", "some" or "somewhere" (case ignored).
- Modify: `Extraction/ExtractionQueue.swift` (`storeCandidates`) and `Confirmation/CandidateActions.swift` (`planEntity`, the place branch of `edges(of:)`): a place whose text is generic makes no entity and no card. `MemoryPlace` still holds the text.
- Tests: `GenericPhraseTests`: "a restaurant", "An old barn", "somewhere up north" are generic; "our house", "Alder Street", "the restaurant", "Andover" are not; empty is not. `EntityExtractionTests`: a kept memory with `place_text` "a restaurant" has the place text and no place entity.
- [ ] Tests first, FAIL. Implement. PASS. **Commit** — `Kit: a place with no name stays text and makes no entity`

### Task 3: Entities with one key become one

- Modify: `Store/EntityRepository.swift`: `merge(_ source: EntityID, into target: EntityID)`, one transaction. It moves, from source to target: `moment_entity` rows (skip a row the target already has for that memory and relation), `entity_span` rows, the entity's tags, and `memory_place` rows that name it. Read `Migrations.swift` and list every table with an entity id before you write it; write that list in the ledger. If `photo_link` exists (Photos merged), move its rows too, and keep the target's cover.
- Then: `mergeDuplicateTitles()` for places and things, by key and type, the first made stays; and for collections in `ChapterRepository`.
- Modify: `Store/ArchiveRepair.swift`: `Report` gains `joinedEntities` and `joinedCollections`. `notice` follows the copy in Global Constraints.
- Tests: `EntityMergeTests`: links move and none doubles; a memory linked to both keeps one link; a hidden or excluded flag on either side stays set on the one that stays; merge with itself or a missing id does nothing; "Ohio." and "Ohio" become one and a second run does nothing; a place "Ohio" and a thing "Ohio" stay two; two people named "Sam" stay two. `ArchiveRepair`: the three notice forms.
- [ ] Tests first, FAIL. Implement. PASS. **Commit** — `Kit: places, things and collections with one name are joined by the repair`

### Task 4: The owner is never a person

- Create: `Domain/OwnerNames.swift`: the match keys of the owner's typed name and aliases, and `func isOwner(_ text: String, relation: String?) -> Bool`: true when the key matches and `relation` is nil or empty (spec edge case: "my cousin Jordan" stays a person).
- Modify: `Store/PeopleRepository.swift`: `findPerson(matching:)` never returns the owner.
- Modify: `Extraction/ExtractionQueue.swift`, after validation: drop a person mention and a `people_refs` entry for which `isOwner` is true; an `about_ref` that pointed at that mention's `ref` becomes "self".
- Add: `PeopleRepository.addOwnerAlias(_:)`, for "That's me" (A2c).
- Tests: `OwnerNamesTests` (name, alias, case, a relation keeps the person, no owner). `ExtractionQueueTests`: output with the owner's name as a mention stores no mention and no card; `about_ref` to it is stored as "self"; with `relation_text` "my cousin" the mention stays.
- [ ] Tests first, FAIL. Implement. PASS. **Commit** — `Kit: the owner's own name is never a person mention`

### Task 5: `about_ref` is checked, and can point at a new person

- Modify: `Extraction/OutputValidator.swift`: `about_ref` must be empty, "self", an entity or person id in the packet, or a `ref` in the same output. The validator needs the packet's ids: add a parameter. A bad value is cleared; the memory is kept. (The spec asked for one retry first; a retry costs a model call for a field that can safely be empty. Write this ruling in the ledger and in `DECISIONS.md`.)
- Modify: `Confirmation/CandidateActions.swift` (`aboutEntity`): a `ref` that names a person mention resolves to that person when the mention is resolved. When it is not resolved yet, the memory is kept with no detail link, and `PeopleRepository.resolve` adds the link when the person answers "Who's this?". One transaction with the resolve.
- Tests: `OutputValidatorTests`: each allowed form passes; an unknown id is cleared and the memory stays. `DetailMachineryTests`: a fact about a known name links at Keep; a fact about a new name links when the mention is resolved to an existing person and to a new person; "Not a person" makes no link; an event never gets a detail link.
- [ ] Tests first, FAIL. Implement. PASS. **Commit** — `Kit: about_ref is validated and follows a person once named`

### Task 6: Group phrases

- Create: `Domain/GroupPhrase.swift`: `static func isGroup(_ text: String) -> Bool`, true when the last word is one of the spec's plural kin words, with or without a possessive before it.
- Modify: `Extraction/ExtractorOutput.swift`: `MentionKind` gains `group`. Fix every `switch` the compiler names. `entityType` for a group: none; make the property optional or guard the callers, whichever changes fewer call sites, and say which in the ledger.
- Modify: `Extraction/ExtractionQueue.swift`: a person mention for which `isGroup` is true is stored as a group. A group mention with a memory that carries it becomes a follow-up of that memory.
- Add: `CandidateActions.resolveGroup(_ candidate:, people: [PersonID], new: [String])` and `leaveGroupAsSaid(_:)`. Each chosen person is linked to the memory as a mention. No alias is written. The mention is marked resolved.
- Add: `PeopleRepository.removeAlias(_ text:, from person:)`. It changes no memory.
- Tests: `GroupPhraseTests` ("our parents", "my grandparents", "the kids", "Parents" are groups; "my parent", "Mom and Dad", "Maya" are not). `GroupMentionTests`: two people chosen gives two links and no alias; "Leave it as said" links nobody and the card does not return; the same phrase in a later segment asks again; a v6 payload with kind `person` and text "our parents" is stored as a group. `PeopleRepositoryTests`: removing a name keeps every link and stops a later match.
- [ ] Tests first, FAIL. Implement. PASS. **Commit** — `Kit: a phrase for several people is a group, never one person's name`

### Task 7: The stored title of a fact, feeling or goal

- Create: `Domain/MemoryLabel.swift`: `static func storedTitle(quote: String) -> String` (the cleaned quote from `ReadableQuote`, at most 8 words, cut at a word, never empty when the quote has a word) and `static func heading(for memory: Memory) -> String` (the title for a moment; the cleaned quote in quotation marks for the rest).
- Modify: `Extraction/OutputValidator.swift`: an empty title is accepted for a fact, feeling or goal. `ExtractionQueue.isBlank` must not treat such a memory as blank; read it and add a case.
- Modify: `Confirmation/CandidateActions.swift` (`acceptMemory`): for a fact, feeling or goal the stored title is `storedTitle(quote:)`, whatever the model sent.
- Tests: `MemoryLabelTests` (a long quote is cut at 8 words; fillers go; a one-word quote; the heading for each kind). `CandidateActionsTests`: a kept feeling with model title "our most formative experiences together" stores "I think we had some of our" as its title; a kept event keeps the model's title. `OutputValidatorTests`: an empty title on an event is still a problem.
- [ ] Tests first, FAIL. Implement. PASS. **Commit** — `Kit: a fact, feeling or goal stores the start of its quote, not a made-up title`

---

## A2b — the prompt (`v7-prompt`)

### Task 1: `extractor.v7.md`

- Create: `Extraction/Prompts/extractor.v7.md` from v6. Rules 1 to 4 unchanged. New or changed text, each from the spec:
  - the speaker is the owner; the owner's name and "I" are never a person mention; `about_ref` is `self` for them;
  - set `about_ref` on a fact, feeling or goal whenever the segment names who or what it is about;
  - a moment's title names the moment, in sentence case, 3 to 8 words; a fact, feeling or goal has an empty title;
  - a phrase for more than one person is a `group` mention; two names said together are two person mentions;
  - a place with no name is `place_text` only; a passing phrase is not an idea.
- Tests: `ExtractorSchemaTests`: v7 loads; rules 1 to 4 of v6 and v7 are equal strings; v7 contains each new rule's key words.
- [ ] Tests first, FAIL. Write the prompt. PASS. **Commit** — `Extractor v7: the prompt`

### Task 2: The packet carries the owner's name

- Modify: `Extraction/ContextPacket.swift`: field `owner` with `name` and `aliases`; absent with no typed name. It is never dropped by the token budget. `docs/OVERVIEW.md` must say that the packet carries the name.
- Tests: `ContextPacketTests`: present with a name; absent without; kept under a tight budget.
- [ ] Tests first, FAIL. Implement. PASS. **Commit** — `Packet: the owner's name, so the model knows who speaks`

### Task 3: Old payloads still decode

- Tests only, unless one fails: a stored v6 candidate payload decodes; a mention with kind `group` round-trips; `ExtractorSchema.json` lists `group`.
- [ ] **Commit** — `Tests: v6 payloads decode beside v7`

### Task 4: Transcripts for each audit case

- Create under `Tests/Fixtures/`: invented transcripts where the owner says their own name; a fact names a new person; a place is said twice with different punctuation; a generic place; a story retold across two sessions; a feeling about a named person; "our parents" beside a named person. Add them to the fixtures README.
- [ ] **Commit** — `Fixtures: a transcript for each audit case`

### Task 5: The comparison

- Modify: `ExtractorIntegrationTests.swift` (runs only with `ANTHROPIC_API_KEY`): run v6 and v7 over every fixture and print one table: person mentions that are the owner; facts, feelings and goals with and without `about_ref`; moment titles not in sentence case; facts, feelings and goals that carry a title; group phrases returned as one person; generic places as entities.
- [ ] Run it on the Mac with a key. Paste the table into the PR and the ledger. **Stop and show the owner.**

### Task 6: v7 is the default

- Only after the owner's yes. Modify: `Extraction/ExtractorConfig.swift` (`version` "v7") and the test that pins it.
- [ ] **Commit** — `Extractor v7 is the default`

---

## A2c — the app (`v7-app`)

### Task 1: The repair runs at launch and says so once

- Modify: `ios/Lifeline/Dependencies.swift` (`live()` and `uiTesting()`): run `ArchiveRepair.run` after the store opens; keep `report.notice`.
- Show the notice once, above the record bar, in the slot You uses (`YouNoticeSlot` in `Screens/You/YouScreen.swift`). Move the slot to `Screens/Shell/` so every tab can show it; do not copy it.
- UI test: `-uiTesting-seedDuplicates` (three stories with one title, "Ohio." and "Ohio"); the notice shows once and not after a relaunch; the Timeline shows one story.
- [ ] **Commit** — `The launch repair runs, with one notice`

### Task 2: "That's me"

- Modify: `Screens/Cards/WhoIsThisCard.swift`, `MentionChoice` (a new case), `CardHandler`. Shown only with an owner.
- UI test in `EntitiesUITests` or a new class: the choice adds no person; the same name in the next scripted segment raises no card.
- [ ] **Commit** — `Who's this: "That's me"`

### Task 3: The group card

- Create: `Screens/Cards/GroupPicker.swift`. Modify: `FollowUpChip.swift`, `CardHandler.swift`, `CardFlow.swift`.
- UI test: tick two people; both show on the memory; the People list shows no new name on either.
- [ ] **Commit** — `A group phrase asks who, and takes several`

### Task 4: "Other names" on a person's page

- Modify: `Screens/Entities/EntityScreen.swift`, `EntityViewModel.swift`. A notice with Undo for 6 seconds.
- UI test: remove a name; the page keeps its moments.
- [ ] **Commit** — `A person's page lists the other names, each with Remove`

### Task 5: The Change sheet and headings for what is not a moment

- Modify: `Screens/Cards/ChangeSheet.swift` (order and headings per the spec; no title field), `Screens/Cards/MemoryCard.swift` and `Screens/Memory/MemoryScreen.swift` (heading from `MemoryLabel.heading`).
- UI tests: a feeling's sheet has no "The title" and leads with "About whom or what?"; a moment's sheet is unchanged (the existing assertions stay).
- [ ] **Commit** — `The Change sheet asks about a scene only for a moment`

### Task 6: Docs, screenshots and the device check

- `docs/OVERVIEW.md`, `README.md` Status, a device checklist at `docs/plans/2026-11-16-extractor-v7-device-check.md`: say your own name in a story; say "our parents"; tell a feeling about a named person; check its page; back up first, then confirm the repair's notice and that the duplicates are one.
- [ ] Whole UI suite once. **Commit** — `Docs: extractor v7 and its device checklist`

---

## After A2

- **A3, the second read,** waits for owner's call 4 (may it change a kind?). The comparison table from A2b Task 5 is the evidence for that call.
- **The fresh read** the owner asked about (v7 over every transcript into a separate copy) is not specified. It could reuse A2b Task 5's runner with the `lifeline` command's `--db` option.
