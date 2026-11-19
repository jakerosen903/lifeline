# PC-d: The Extractor Tells People Apart — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Approved by the owner on 2026-11-19 ("Yes, build both"), without a review of each decision. Each decision stays open to an overrule.

**Goal:** Two people with one name in one recording become two people, and one person said under two names becomes one. The extractor gives each person in a recording a handle, and the app groups and guesses by that handle.

**Architecture:** A new prompt version, `v8`, returns a list of people with handles. A memory names its people by handle. The context packet carries the handles of the recording so far. After validation the app copies each handle's said name into the memory card, so every part of the app that reads a said name works as before. Keep writes the handle on the link, uses it as the group, and never gives two handles of one name the same person. No migration: `v15` has `moment_entity.person_handle`. No screen changes.

**Tech Stack:** Swift 6, GRDB, Swift Testing, XCUITest, the Anthropic Messages API with a JSON schema. No new dependency.

**Spec:** `docs/specs/2026-11-18-people-contacts.md`, section "Step 2: the extractor tells people apart", and its lines on the group ("Settling a guess") and on details ("Moving a name", point 2).

**Not this plan:** PC-c (merge two people; plan `docs/plans/2026-11-19-people-contacts-c.md`). The unmerged `v7` prompt (branch `v7-prompt`, plan `docs/plans/2026-11-16-extractor-v7.md`).

**Worktree and branch:** `.claude/worktrees/people-contacts-16241d`. Branch `people-contacts-d`, cut from `people-contacts-b` (`8c882a9`, PR #35). The PR's base is `people-contacts-b`. No AI attribution in a commit or in PR text. Nothing goes to production.

---

## What the owner gets

1. A story that says "Robyn from work" and later "the other Robyn, my cousin" gives two people, each with its own chip. Today both become one person.
2. A story that says "Robyn" and later "my roommate" for the same person gives one person, when the story's words make that clear.
3. "Yes, this Robyn" with the checkbox on settles the links of that one person in the recording, not every link that happens to share the said name.
4. Every guess is still marked "Assumed". The model's opinion never removes a mark.

## Decisions made in this plan

1. **The prompt is `v8`, written from `v6`.** `v6` is the default on this branch. `v7` exists only on the unmerged branch `v7-prompt` and waits for the owner's yes. This plan does not depend on it. When `v7` merges, its rules (the owner's name, groups) are joined into the next version by a small merge of two text files.
2. **`v8` does not become the default in this plan's first PR.** Tasks 1 to 6 build and test it with `v6` still the default. Task 7 compares `v6` and `v8` on test stories with the real model and writes a table. Task 8 switches the default only after the owner reads the table and says yes. The `v7` plan set this gate, and this plan keeps it.
3. **The comparison uses the owner's Anthropic key on the Mac.** It makes about 60 model calls on invented stories. It does not run in CI. With no key in the environment, Task 7 stops and says so.
4. **A memory card stores its people.** After validation the app writes, into the card, each handle with its said name, relation phrase and person id. Keep reads the card only. A card extracted by `v6` has no handles and works by said name, as today.
5. **`people_refs` stays in the card, filled by the app** with the said name of each handle. The validator, the owner's-name filter, the chips and the follow-up code read said names and do not change.
6. **The model's person id is used only inside rule 4.** When the id names one of the candidates that rule 4 already has, that candidate is chosen in place of the most recently linked one. The link is `assumed`. An id that names no candidate of rule 4 is dropped. The spec says the id "decides the choice in rule 4"; this plan gives it no other power.
7. **A handle that the recording already linked keeps its person.** A later card with that handle takes the same person. The origin is the earlier link's origin when that is `said` or `new`, and `assumed` in every other case. A `confirmed` earlier link gives `assumed`: the owner confirmed that card, not this one. (Narrowed by ruling D29 after the final review: the earlier `said` or `new` carries only when the later card says the same name in its own segment.)
8. **A stored choice is keyed by the said name and the handle.** `candidate_person_choice` has the key (`candidate_id`, `said_name`). For a card with handles, the stored `said_name` is the normalized said name, a separator, and the handle. This needs no migration, and two people with one name on one card keep two answers.
9. **Three places stay on the said name:** the contact re-guess after access is given (`ContactCheck.reguess`), the people of a telling that is separated (`MergeActions.people(named:)`), and follow-up chips. Each works on one link at a time, where the handle adds nothing.
10. **The schema sent to the model changes for every version.** The schema is not versioned. A `v6` call after this plan must also return the new keys. `v6` stays only as the default until Task 8, so Task 1 gives `v6` one added line that says: return `people` empty and `person_handles` empty. This is the smallest change that keeps `v6` valid.

### Limits found while planning

- **No score exists for prompt quality.** The only measure is the table of Task 7, read by the owner.
- **A wrong handle from the model joins or splits people.** "Someone else…" repairs a wrong join today. A wrong split needs the merge of PC-c.
- **The packet shows the model at most two earlier segments of text.** The handles of the whole recording are sent, with their said names, so a handle holds across a long recording.
- **Old recordings do not change.** Links made before this plan have no handle and group by said name.

---

## Global Constraints

- A handle is a short text ("p1"). It means one person inside one recording. It has no meaning in another recording.
- A person id from the model is accepted only when the packet of that call holds it. Any other id is cleared.
- A link made with the help of the model's person id has origin `assumed`. Only the owner's action makes a link `confirmed`.
- Two handles with one said name in one recording never get the same person from a guess. The second takes the next candidate in order. With no other candidate it is a new person (rule 7).
- Two handles that the owner settles to one person in one memory share that memory's one link.
- Every said name in the card is copied from the segment. The validator must reject a person whose said name is not a run of words in the segment, as it rejects a `people_refs` entry today.
- The owner is never a person in the list, and never a candidate.
- **Nothing from a contact goes to the model.** The packet's new field holds only said names, relation phrases, handles and the ids of people the packet already lists.
- The schema must stay under the API's limit of 16 union-typed parameters. Every new key is a plain string or an array of strings; "" means none.
- A card written by an earlier version must decode and Keep as today.
- Every rule of the Global Constraints of PC-a and PC-b still binds.
- Fixtures and test stories are invented. No real person's data.
- Add each ruling made while building to `.superpowers/sdd/2026-11-19-people-contacts-d/rulings.md` and keep `progress.md` current. Commit both.

## Review Focus

1. **Two people with one name on one memory card** ("Robyn from work met my cousin Robyn"). Expected: two chips, two people, two stored answers that do not overwrite each other. Tests in Tasks 4 and 5.
2. **The model reuses a handle for a different person by mistake.** Expected: both names go to one person, each link is marked "Assumed", and "Someone else…" on one link with the checkbox off moves that link only. Test in Task 5.
3. **The model sends a person id that the packet does not hold, or the owner's id.** Expected: the id is cleared and the guess runs as if none was sent. Test in Task 3.
4. **The default version changes while segments wait.** `ExtractionQueue` skips a segment that has candidates of the current version only. Expected: a segment that already has cards from `v6` gets no second set of cards from `v8`. Test in Task 8.
5. **A continuation card across segments names a handle of the earlier segment.** Expected: the earlier card gains the person once, with the same handle. Test in Task 3.

---

### Task 1: The output types, the schema and the `v8` prompt

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Extraction/Prompts/extractor.v8.md`
- Modify: `Extraction/ExtractorOutput.swift`, `Extraction/ExtractorSchema.swift`, `Extraction/OutputValidator.swift`, `Extraction/Prompts/extractor.v6.md` (one line, decision 10), `Extraction/ScriptedExtractionService.swift` (the removed argument)
- Test: `ExtractorSchemaTests.swift`, `ExtractorOutputTests.swift`, `OutputValidatorTests.swift`; fixture `Tests/Fixtures/extractor-output-two-robyns.json`

**Interfaces:**
- Produces:
  ```swift
  /// One person the extractor found in the recording.
  public struct PersonOut: Codable, Sendable, Equatable {
      public var handle: String          // "p1"
      public var saidName: String        // the name as said in this segment
      public var relationText: String?   // "" decodes as nil
      public var personID: String?       // a packet person's id; "" decodes as nil
  }
  // ExtractorOutput gains:  public var people: [PersonOut]          // JSON "people"; missing decodes as []
  // MemoryOut gains:        public var personHandles: [String]      // JSON "person_handles"; missing decodes as []
  //                         public var handlePeople: [PersonOut]    // JSON "handle_people"; written by the app (Task 3), not in the schema
  // MentionOut gains:       public var handle: String?              // JSON "handle"; "" decodes as nil; for a person mention
  // MentionOut loses the init argument `likelyAliasOfPersonID`; the key still decodes and is ignored.
  ```
- Schema: top-level `people` (array of objects with `handle`, `said_name`, `relation_text`, `person_id`, all strings); memory `person_handles` (array of strings); mention `handle` (string). `likely_alias_of_person_id` leaves the schema. `people_refs` stays.
- Validator: a person whose `said_name` is not a run of words in the segment is dropped, and each memory that names its handle is rejected with the reason "person_handles not in people: {handle}". A memory with a handle that the `people` list does not hold is rejected the same way. A duplicate handle in `people` keeps the first.

The `v8` prompt is `v6`'s text with these changes to the people passages:
- A new rule: "List every person the segment mentions in `people`, one entry per person. Give each a `handle`. The packet's `recordingPeople` lists the people of this recording so far: use the same handle for the same person, and a new handle for a new person. Two people with the same name get two handles. One person said under two names gets one handle."
- "`said_name` is the name as said in this segment, copied exactly; use the kin phrase only when no name is said. `relation_text` is the kin or role phrase said with it, or "". `person_id` is the id of a person in the packet only when the words of the story point to that person; otherwise ""."
- "`person_handles` on a memory lists the handles of the people in that memory. Leave `people_refs` empty."
- "A person mention carries the `handle` of that person."
- "`about_ref` may also be a handle."

- [ ] **Step 1: Write the failing tests.**
  - The fixture decodes: two people "Robyn" with handles "p1" and "p2", relation texts "from work" and "my cousin", and two memories with one handle each.
  - A `v6` payload (no `people`, no `person_handles`, with `likely_alias_of_person_id`) decodes with empty lists.
  - "" for `relation_text`, `person_id` and a mention's `handle` decodes as nil.
  - `schemaStaysUnderTheUnionLimit` still passes; the schema has `people` and `person_handles` and no `likely_alias_of_person_id`.
  - `ExtractorPrompt.system(version: "v8")` loads and names `recordingPeople`, `person_handles` and "two handles".
  - Validator: a person with a said name not in the segment is dropped and its memory is rejected; a memory with an unknown handle is rejected; a duplicate handle keeps the first.
- [ ] **Step 2: Run them.** `swift test --filter "ExtractorSchemaTests|ExtractorOutputTests|OutputValidatorTests"`. Expected: FAIL.
- [ ] **Step 3: Write the code and the prompt.**
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Extractor v8: a list of people with handles, and memories that name them"`

### Task 2: The packet carries the recording's handles

**Files:**
- Modify: `Extraction/ContextPacket.swift`, `Extraction/ExtractionQueue.swift` (`packet(for:)`), `Store/CandidateRepository.swift` (one read)
- Test: `ContextPacketTests.swift`, `ExtractionQueueTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // ContextPacket gains:
  public var recordingPeople: [RecordingPerson]
  public struct RecordingPerson: Codable, Sendable, Equatable { public var handle: String; public var saidNames: [String]; public var relation: String?; public var personID: String? }
  // ContextPacketBuilder.build gains the argument `recordingPeople: [RecordingPerson] = []`
  // CandidateRepository gains: func handlePeople(inSession: SessionID, before segment: SegmentID) throws -> [PersonOut]   // from the memory cards of earlier segments, in order
  ```
- One entry per handle. `saidNames` holds each distinct said name of that handle, in the order said. `relation` and `personID` are the first that were given. `personID` is sent only when the packet's `people` holds that id.
- Trim order: `recordingPeople` is dropped after `people` and before `memories`. It keeps its first entry, as each section does.

- [ ] **Step 1: Write the failing tests.**
  - Two earlier cards with "p1" said as "Robyn" and later as "my roommate": one entry with both said names.
  - A card of the current segment and a card of another session add nothing.
  - A dismissed card adds nothing; a kept card and a waiting card both add.
  - The encoded packet holds the key `recordingPeople`.
  - Under a small budget, `people` trims before `recordingPeople`.
  - A person id that the packet's `people` does not hold is left out.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.**
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "The context packet carries the handles of the recording so far"`

### Task 3: The card stores its people

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Extraction/HandleResolve.swift`
- Modify: `Extraction/ExtractionQueue.swift` (`process`, after `AboutRefCheck`), `Extraction/AboutRefCheck.swift` (a handle is a known ref), `Domain/OwnerNames.swift` (`removingOwner` also drops an owner entry of `people` and its handle from each memory), `Store/CandidateRepository.swift` (a continuation adds its `handlePeople` to the earlier card)
- Test: `HandleResolveTests.swift`, `ExtractionQueueTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum HandleResolve {
      /// For each memory with handles: `handlePeople` = the people of its handles, with a person id kept only when `knownPeople` holds it;
      /// `peopleRefs` = their said names, in handle order. A memory with no handle is not changed.
      static func resolved(_ output: ValidatedOutput, knownPeople: Set<String>) -> ValidatedOutput
  }
  ```
  (`ValidatedOutput` stands for the type `OutputValidator.validate` returns.)
- A person mention whose `handle` a memory of this output carries is a carried name, as a mention with the same text is today (`CarriedName`).

- [ ] **Step 1: Write the failing tests.**
  - A memory with handles "p1" and "p2" gets `handlePeople` of two and `peopleRefs` ["Robyn", "Robyn"].
  - Review Focus 3: a person id not in `knownPeople`, and the owner's id, are cleared.
  - The owner's name as a person: the entry and its handle are removed, and the memory stays.
  - `about_ref` equal to a handle survives `AboutRefCheck`.
  - A `v6` output passes through with no change.
  - Review Focus 5: a continuation row with handle "p1" extends the earlier card: its `handlePeople` holds "p1" once.
  - A person mention with handle "p1" that a memory carries is stored `accepted` and shown on no card.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.**
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "A memory card stores the people its handles name"`

### Task 4: Keep guesses by handle and writes the handle

**Files:**
- Modify: `Confirmation/PersonGuess.swift`, `Confirmation/PersonGuessOnKeep.swift`, `Confirmation/CandidateActions.swift` (`edges`, `aboutEntity`), `Confirmation/PersonLinkActions.swift` (`preview`, `PreviewChip`), `Domain/Memory.swift` (`MemoryPerson`), `Store/PersonLinkRepository.swift`, `Store/PersonLinkWrites.swift` (`storeChoice`)
- Create: `ios/LifelineKit/Sources/LifelineKit/Confirmation/ChoiceKey.swift`
- Test: `PersonGuessTests.swift`, `PersonGuessOnKeepTests.swift`, `PersonLinkActionsTests.swift`, `ChoiceKeyTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // PersonGuess
  public static func guess(_ said: SaidName, people: [Known], contacts: [Contact], modelPick: PersonID? = nil, taken: Set<PersonID> = []) -> Result
  //   `taken`: persons another handle of the same said name already has in this recording; they are not candidates.
  //   `modelPick`: decision 6.

  // MemoryPerson gains: public var handle: String? = nil     // written to moment_entity.person_handle
  // PreviewChip gains:  public var handle: String?            // `id` becomes ChoiceKey.text(saidName:handle:)

  enum ChoiceKey {
      /// The normalized said name; with a handle, the said name, the separator U+001F and the handle (decision 8).
      static func text(saidName: String, handle: String?) -> String
  }

  // PersonLinkRepository gains:
  func handleLinks(inSessionOf segment: SegmentID) throws -> [(handle: String, saidKey: String, person: PersonID, origin: LinkOrigin?)]
  // PersonLinkActions.choose gains the argument `handle: String? = nil`
  ```
- `edges(of:for:segment:card:)` walks `out.handlePeople` when the card has any, else `out.peopleRefs` as today. For each handle, in order:
  1. A stored choice under `ChoiceKey` wins, origin `confirmed`.
  2. A handle the recording already linked, or this card already planned, takes that person (decision 7).
  3. Otherwise `PersonGuess.guess` with `taken` = the persons that other handles with the same said-name key hold in this recording or on this card, and `modelPick` = the card's person id for that handle.
- The relation phrase of a handle comes from `handlePeople`, not from a person card of the segment.
- `aboutEntity`: an `about_ref` that is a handle follows that handle's link.

- [ ] **Step 1: Write the failing tests.**
  - `PersonGuess`: with two persons "Robyn" on file, `modelPick` of the older one chooses it, origin `assumed`; `modelPick` of a person with another name is ignored; `taken` holding the most recent one chooses the next; `taken` holding both gives a new person (rule 7); rules 1 and 2 ignore `modelPick`.
  - Review Focus 1: one card with "p1" and "p2", both "Robyn", one person "Robyn" on file. Keep links the person on file for "p1" and makes a new person for "p2". Two links, with handles "p1" and "p2".
  - Two cards in one recording with "p1": the second links the same person. Earlier origin `new` gives `new`; earlier `confirmed` gives `assumed`.
  - Two cards in two recordings with "p1": the second runs its own guess.
  - One handle said as "Robyn" on one card and "my roommate" on the next: one person, and the first said name stays on the first link.
  - A stored choice for "p2" does not change "p1" on the same card.
  - The preview of a waiting card shows the chips that Keep writes, with their handles.
  - A fact whose `about_ref` is "p2" is a detail of the person of "p2".
  - A `v6` card with no handles keeps and previews as before (the existing tests stay green).
  - `moment_entity.person_handle` holds the handle after Keep.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.**
- [ ] **Step 4: Run `swift test`.** Expected: PASS, and `noExtractionPathCallsFindPerson` still passes.
- [ ] **Step 5: Commit.** `git commit -m "Keep guesses by handle: two handles of one name are two people"`

### Task 5: The group is the handle

**Files:**
- Modify: `Domain/PersonLink.swift`, `Store/PersonLinkRepository.swift` (`fetch`, `group(of:)`), `Store/PersonLinkWrites.swift` (`details(about:mentionedIn:)`), `ios/Lifeline/Screens/People/WhoIsThisViewModel.swift` (passes the chip's handle to `choose`)
- Test: `PersonLinkRepositoryTests.swift`, `PersonLinkActionsTests.swift`

**Interfaces:**
- Produces: `PersonLink` gains `public var handle: String?`.
- `group(of:)`: for a link with a handle, the links of the same person in the same recording with the same handle. For a link with no handle, today's rule by said name.
- `details(about:mentionedIn:)`: a detail moves with a link when its card's `about_ref` names the same handle, or, with no handle, the same said name.

- [ ] **Step 1: Write the failing tests.**
  - Settle with the checkbox on: two links with "p1" are settled; a link of "p2" with the same said name and the same person is not.
  - Review Focus 2: "Robyn" and "Robin" share "p1" and one person. A move of one link with the checkbox off moves that link only; with it on, both.
  - A move of "p1" takes the fact whose `about_ref` is "p1" and leaves the fact about "p2".
  - Links with no handle group by said name (the existing tests stay green).
  - Undo of a move restores the handles.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.**
- [ ] **Step 4: Run `swift test`, then build the app.** Expected: PASS and BUILD SUCCEEDED.
- [ ] **Step 5: Commit.** `git commit -m "A guess's group is the extractor's handle"`

### Task 6: The scripted extractor and one UI test

**Files:**
- Modify: `Extraction/ScriptedExtractionService.swift`, `ios/Lifeline/UITestSeed.swift` (only when the seed of guesses needs a second "Robyn")
- Test: `ScriptedExtractionServiceTests.swift`, `ios/LifelineUITests/PeopleGuessUITests.swift`

- The scripted service gives each person it scripts a handle, through the same `HandleResolve` path as the real service.
- A new launch flag `-uiTesting-twoRobyns` scripts one segment with two people "Robyn": "Robyn from work" and "my cousin Robyn".

- [ ] **Step 1: Write the UI test** `testTwoPeopleWithOneNameGetTwoChips`: record with the flag, the memory card shows two chips for "Robyn", Keep, and the People grid has two tiles "Robyn". The sheet of one chip changes that person only.
- [ ] **Step 2: Write the code.**
- [ ] **Step 3: Run `PeopleGuessUITests`, `PeopleContactsUITests` and `LandingUITests`** on the simulator "Lifeline People". Expected: PASS.
- [ ] **Step 4: Commit.** `git commit -m "The scripted extractor gives handles; two Robyns get two chips"`

### Task 7: Test stories and the comparison

**Files:**
- Create: `ios/LifelineKit/Tests/Fixtures/transcript-v8-two-robyns.json`, `transcript-v8-two-names.json`, `transcript-v8-name-alone.json`, `transcript-v8-new-relation.json`; `ios/LifelineKit/Tests/LifelineKitTests/HandleTally.swift`, `HandleTallyTests.swift`; `docs/experiments/2026-11-19-extractor-v8-handles.md`
- Modify: `ExtractorIntegrationTests.swift`

The four stories are the spec's: two people with one name in one recording; one person under two names; a name with no other words; a known name with a new relation phrase. Each has two or three segments, so a handle must hold across segments. Each has an expected answer beside it: how many people, and which said names share a person.

**Interfaces:**
- Produces: `HandleTally` (pure): from the outputs of one story's segments, the number of distinct handles, the said names of each, and whether the story's expected answer holds.

- [ ] **Step 1: Write the stories and `HandleTallyTests`** (the tally on hand-written outputs).
- [ ] **Step 2: Add the comparison to `ExtractorIntegrationTests`**, enabled only with `ANTHROPIC_API_KEY`: each story and the three older fixtures, through `v6` and `v8`, three runs each. It asserts only what must hold for every version: no shown field holds text that is not in the transcript, and every handle of a memory is in `people`. It prints one table: story, version, run, people found, expected, pass.
- [ ] **Step 3: Run it** with the key. With no key: stop, write a ruling, and tell the owner the one command to run.
- [ ] **Step 4: Write the result** in `docs/experiments/2026-11-19-extractor-v8-handles.md`: the table, each miss in plain words, and whether `v8` lost anything `v6` had on the three older fixtures (memories found, mentions found).
- [ ] **Step 5: Commit.** `git commit -m "Test stories and a v6 against v8 comparison for handles"`

### Task 8: Docs, the ledger, and the default after the owner's yes

**Files:**
- Modify: `docs/specs/2026-11-18-people-contacts.md` (narrowed notes for decisions 6, 7 and 8), `docs/DECISIONS.md`, `docs/OVERVIEW.md` (the extractor's output and the packet), this plan ("What changed while building")
- After the owner's yes only: `Extraction/ExtractorConfig.swift` (`version: "v8"`), the tests that pin "v6", `Extraction/Prompts/extractor.v6.md` stays in the bundle.

- [ ] **Step 1: The docs and the ledger.** Commit.
- [ ] **Step 2: Run everything.** `swift test` and the whole UI suite. Record the counts and every failure in the ledger.
- [ ] **Step 3: Open the PR** on `people-contacts-b`, with `v6` still the default. The PR text says so, cites principles 1 and 5, and links the table of Task 7.
- [ ] **Step 4: Stop for the owner's yes on the table.**
- [ ] **Step 5: After the yes, switch the default.** First the test for Review Focus 4: a segment with `v6` cards and status `extracted` is not extracted again when the service's version is `v8`; a segment with status `pending` and `v6` cards is closed out, not extracted again. Then change `ExtractorConfig` and the pinned tests. Run `swift test`. Commit: "v8 is the default extractor prompt".

---

## After PC-d

- A device check: one real recording with two people of one name, and one with a person under two names.
- When `v7` gets its yes, its rules join the current prompt as the next version.

## What changed while building

The full record is the ledger: `.superpowers/sdd/2026-11-19-people-contacts-d/rulings.md` (D1 to D31) and `progress.md`.

- **Task 4b was added (ruling D17).** The validator rule of Task 1 rejected a memory that names a handle of an earlier segment with no `people` entry in its own output. That is the case a handle exists for ("She was always late"). Now a handle of the recording so far is valid in `person_handles` and `about_ref`. The card stores the recording's entry, with its first said name.
- **Task 7b was added (ruling D25).** A person named in a segment that gives no memory card did not reach the next segment's `recordingPeople`. Now `recordingPeople` also reads the person mentions of earlier segments that carry a handle. The comparison also writes each table row as it is made, so a failed run keeps the rows.
- **D22.** A handle in `about_ref` is always also one of that memory's people. The `v8` prompt says so. `HandleResolve` adds the handle to the memory's `personHandles` when the model left it out.
- **D16 reverses part of decision 9.** `separateTelling` finds a telling's people by handle when the links have handles. Two handles of one name in one memory would otherwise move both or neither. The contact re-guess and the follow-up chips stay on the said name.
- **D1 keeps the init argument.** `MentionOut.init` keeps `likelyAliasOfPersonID`, with a default of nil. The schema and the prompt drop the key, and the decoder ignores it. Task 1 planned to remove the argument.
- **The comparison makes about 140 model calls, not 60** (decision 3): 23 segments, 2 versions, 3 runs. It has not run: the build environment has no key.
- **The final review's fix wave (rulings D29 to D31).** D29 narrows decision 7: a carried handle keeps the earlier `said` or `new` only when the later card says the same name in its own segment, and a carried origin never changes an existing link. D30: `recordingPeople` holds the handles of every other segment of the recording, earlier and later. A memory folded into a memory of another recording leaves its handles behind. Settle and move read the relation phrase of the link's own handle. D31 parks one limit: two handles that the owner settles to one person keep only the first handle.
