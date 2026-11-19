# SDD ledger — plan: docs/plans/2026-11-19-people-contacts-c.md

Branch `people-contacts-c`, cut from the tip of `people-contacts-d` (5bf37b2). Spec: `docs/specs/2026-11-18-people-contacts.md`, "Merging two people".
The owner said "Yes, build both" (PC-d, then PC-c) on 2026-11-19, without a review of each plan decision.

## Pre-flight scan

| Tasks | Produces against consumes | Found |
| --- | --- | --- |
| 1 | The branch | The base already has `main`'s photo order and `v16`. The task is done by cutting the branch. `PhotoRepository.writeOrder` is still `private`. Ruling C1. |
| 2 and 3 | `PersonMergeReceipt` public fields (2); the row copies (3) | Task 2 may leave the copies empty. Agree. |
| 2 | Step 9 failure test drops `domain_tag` | The plan's transaction-failure test needs a step that throws; dropping a table is the plan's way. Agree. |
| 2 and PC-d | Links carry `person_handle` | `update or ignore` moves the row with its handle. A memory both persons link keeps the stayer's row and handle. Ruling C2. |
| 3 | Undo list against the owned tables | `photo_page_declined` is a real table on this base; the plan's "when it exists" guard stays, since the kit can open an older database copy in tests. Agree. |
| 4 and 5 | `PersonMoveUndo.offer`; `PersonMergeViewModel.ask` | Agree. |
| 4 and 6 | `PersonMergeSheet(picker:)`; the grid's slot | Agree. |
| 5 | Changes a PC-b UI test | The plan names the renamed test. Agree. |
| 6 | The drag test may not run on the simulator | The plan says what to do. |
| 7 | Seeds | `launchWithPeople` has Maya, Dad, Sam, Lena; `-uiTesting-seedContactLink` links Lena. Agree. |
| 8 | Docs | Agree. |

## Progress

- Task 1: complete (the branch `people-contacts-c` exists at cef70ed; no merge of `main` was needed).
