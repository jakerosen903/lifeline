# SDD ledger — plan: docs/plans/2026-11-18-people-contacts.md

Spec: docs/specs/2026-11-18-people-contacts.md. Branch claude/people-contacts-16241d. Plan approved by the owner 2026-11-18, subagent-driven.

## Pre-flight scan

| Tasks | Produces / consumes | Found |
| --- | --- | --- |
| 1 → 3, 4, 5 | LinkOrigin, MomentEntity.origin, Person.createdByGuess / used in links and persons | agree |
| 1 → 3, 5 | table candidate_person_choice (choice text) / PersonChoice read (T3), choose write (T5) | column values not named in the plan. See R1 |
| 2 → 3, 5, 6 | PersonGuess.guess, SaidName.key / Keep, preview, options | agree |
| 3 → 4, 5 | PersonLinkRepository created with known(), choices(for:) / extended | agree; one file grows over three tasks |
| 4 → 5, 6, 7, 8 | PersonLink, group(of:), links(of:), PersonChipLine | links(of:) "never the owner" conflicts with today's memory page. See R2 |
| 5 → 6, 7, 8 | PersonLinkActions.Target, PersonMoveReceipt, PreviewChip | agree |
| 6 → 7, 8 | PersonChip, WhoIsThisSheet, WhoIsThisViewModel.Source | agree |
| 7 ↔ 9 | chips replace FlowChips / older UI tests assert old chips | plan says Task 9 moves them; Task 7 may leave those red. Accepted as written |
| each task alone | tests against code | T1–T6, T9 agree. T7, T8 have no new unit tests (views only); covered by T9 |

## Rulings

- R1: `candidate_person_choice.choice` holds `person`, `contact`, `new` or `not_a_person` (the spec's data model names these) — the plan left the values out — low cost if wrong: one column's strings.
- R2: `PersonLinkRepository.links(of:)` includes the owner when the owner is linked, with whatever origin the row has — today's memory page shows the owner when they typed their own name, and dropping them is a regression the spec does not ask for — if wrong, the owner shows as a chip on a memory page.

## Tasks
- Task 1 (migration v14, LinkOrigin): done, full kit suite 1031 passing.
- Task 1: complete (commits cb141a5..4b6c57c, review clean). Parked for Task 3: the raw-SQL copy sites in MemoryRepository (convert ~379, merge ~446, detail→mention ~584, mention→detail ~614) drop origin and person_handle. See R6.
- Task 2: fix round 1/5 (1 addressed, 0 open — comma-form relation leak in rule 1; commits d751e2d..b9934f6)
- Task 2: complete (commits 8815982..b9934f6, review clean)
- Task 2: minor (deferred): a person linked to a contact whose own name is shorter than the said full name gets rule 4, not rule 3 (same choice, other rule number).
- Task 2: minor (deferred): `SaidName.name` keeps the first non-relation part and drops later ones ("Marcel, Robin"); no comment says so.
- Task 2: minor (deferred): `PersonGuess.Result` has no public initializer.
- Task 2: minor (deferred): a person who matches only through a linked contact and holds the relation alias resolves as assumed, not said.
- Note: `ExtractionQueueTests.drainGivesUpAtItsDeadline` failed once on timing and passed on rerun; not touched by this plan.
- Task 3: implemented (commits 236bb08..310ec90). App target builds (xcodebuild exit 0, controller run). Review: needs fixes — 1 Important (pre-v14 pending person candidates give a second link), R12 ruled (R13).
- Task 3: minor (deferred): `aboutEntity` guesses the detail by the mention text and the mention link by the people ref; with a stored choice keyed on "my roommate, Robin" the detail and the mention can go to two persons. Carry into Task 5 (R9).
- Task 3: minor (deferred): `MergeActions.people(named:in:)` matches only the whole ref's key against role_text; a comma-form ref in the staying telling is missed, so Separate can move a link the remaining telling still names.
- Task 3: minor (deferred): "stored new" sets createdByGuess false; not in a ruling (now R14).
- Task 3: minor (deferred): an old alias that is a group phrase ("our parents") no longer links on Keep; matches the spec; now R15.
- Task 3: minor (deferred): stale doc comment at PeopleRepository.swift:108-109 ("A name the extractor found goes through findPerson").
- Task 3: minor (deferred): guessInputs reads all people and aliases for every segment of a Keep, also when the card names nobody.
- Task 3: minor (deferred): `aCarriedPersonNameShowsNoCard` stops at the queue and does not keep the card.
- Task 3: fix round 1/5 (1 addressed, 0 open — pending person cards closed in the Keep transaction; commits ed405db..59f377d)
- Task 3: complete (commits 236bb08..59f377d, review clean)
- Task 4: complete (commits b639794..ae9df62, review clean). ⚠️ item (which memories the link reads include) ruled as R18.
- Task 4: minor (deferred): no test that a detail link is left out of a mention's group (R16).
- Task 4: minor (deferred): `group(of:)` uses two separate reads; one read would be tidier.
- Task 4: minor (deferred): the owner-order test compares with localizedCaseInsensitiveCompare while SQL uses collate nocase.
- Task 5: implemented (commits 28c8808..18ef780). Review: needs fixes — 1 Important (a fact's own mention can move while its detail stays). Controller promoted four Undo-safety minors and one ruling (a move clears the target's created_by_guess) into round 1, because a wrong Undo writes to the owner's only copy; first-telling rule clarified (moment, mention, not hidden).
- Task 5: minor (deferred): `PersonLinkRepository.db` went from private to internal for the writes file (R22).
- Task 5: fix round 1/5 (7 addressed, 0 open — fact detail follows its mention; move clears guess flag; no-op undo; undo refused after rename or deletion; first telling only from a visible moment; missing tests; commits bee8736..ceeac4e)
- Task 5: complete (commits 28c8808..ceeac4e, review clean)
- Task 5: minor (deferred): Undo's span restore could hit a foreign-key error if a segment were deleted without its memory; the existence checks cover memories and entities only.
- Task 6: complete (commits bd2ff2b..3e21501, review clean). ⚠️ items checked by the controller: Theme.hairline is the card border colour; the writes throw PersonLinkActions.Error; the chip's "Assumed" word comes from the caller (Task 7 must pass PersonChipLine's text and label). Ruling R29.
- Task 6: minor (deferred): `WhoIsThisViewModel.done()` mapping is untested (app target); a pure kit function with a table test would cover it.
- Task 6: minor (deferred): `links(to:)` runs once per person at sheet open (N queries).
- Task 6: minor (deferred): `Theme.secondaryText.opacity(0.6)` on the "Someone new" circle is a derived colour value.
- Task 6: minor (deferred): the sheet's error text is not cleared when the selection changes.
- Task 6: minor (deferred): `who.else` sits on the DisclosureGroup; confirm in a UI test that it addresses the toggle.
- Task 7: implemented (commits e6a5b47..931eeef). Kit 1146 pass, app builds, LandingUITests 14/14, PeopleUITests 10/10. Six older UI tests fail on the removed person follow-up (ExtractionUITests.testWhoIsThisResolvesToANewPerson; FollowUpUITests: testKeepShowsChipsOnTheSameCard, testPersonChipOpensWhoIsThis, testDoneClosesTheKeptCard, testUndoAfterDoneBringsTheChipsBack, testCheckedChipStaysOnSession) — reviewer confirmed the attribution; Task 9 moves them.
- Task 7: review needs fixes — 2 Important (kept-card chips stale after Change…; sheet view model rebuilt on every render) + 1 copy ruling (no raw error text).
- Task 7: minor (deferred, flag for owner): "Not a person" chosen on a waiting card drops the chip with no notice and no way back on that card before Keep (R30).
- Task 7: minor (deferred): the memory page has two pinned bottom slots (photo error, move notice); the spec says one message slot.
- Task 7: minor (deferred): the landing's 1-second poll reruns `preview` for every waiting row and `guessCount` on the main actor.
- Task 7: minor (deferred): `CardHandler.deps` made internal; a `PersonChipRow?` view stored as a property on MemoryCard/KeptCardView.
- Task 7: minor (deferred): `PersonChipRow` reads person covers from the store in `.task`, once per row.
- Task 7: to check in Task 9: run SameStoryUITests, TimelineUITests, SessionDetail and EntityPage classes (not run in Task 7); chips at the largest text size.
