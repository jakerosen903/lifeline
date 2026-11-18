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
