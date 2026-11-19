# SDD ledger — plan: docs/plans/2026-11-18-people-contacts-b.md

Branch `claude/people-contacts-b`, cut from `claude/people-contacts-16241d` at 6e469ca (PC-a with `main` merged in, b55c02f). Spec: `docs/specs/2026-11-18-people-contacts.md`. Owner approved the plan on 2026-11-18 ("Approve, subagents").
Baseline: kit 1295 pass on b55c02f (one timing flake passed alone); app builds; the UI suite on b55c02f was still running under heavy machine load when work began.

## Pre-flight scan

| Tasks | Shared file or interface | Found |
| --- | --- | --- |
| 1 → 2, 5 | `ContactsCache.forGuess` feeds the `contactsForGuess` closure | Agree. Task 2 tests pass contacts through the closure; Task 5 wires the cache. |
| 2 → 5, 6, 7 | `PersonChipLine.text` gains `fromContact` and `contacts` | Task 2 changes a signature the app calls. Ruling PB1. |
| 2 ↔ PC-a | `removeIfEmptyGuess` requires "no contact" (spec, "Moving a name" point 6) | A person Keep made from a contact would never be removed. Ruling PB2. |
| 3 → 4 | `link` clears `created_by_guess`; `reguess` links a person the app made | They disagree. Ruling PB3. |
| 3 → 6, 7 | `ContactLinkActions.link`, `copyPicture` | Agree. |
| 2 → 6 | A planned person from a contact (Keep) and a move to `.contact` | Task 6 must reuse Task 2's builder, with origin `confirmed`. Noted in the Task 6 dispatch. |
| 5, 8 | `UITestSeed.swift`, launch argument `-uiTesting-contacts` | Task 5 adds the argument and cards; Task 8 adds people. No conflict. |
| 6, 7 | `ContactSearchList` | Task 6 creates it; Task 7 uses it. Order holds. |
| 1 | own text | Agrees. `ScriptedContactsDirectory` is a settable `Sendable` class: it needs a lock. |
| 2 | own text | Agrees. |
| 3 | own text | Agrees. |
| 4 | own text | Agrees. `check()` needs `all()` for the re-link by name; the protocol has it. |
| 5 | own text | The only test is the pure rule; the rest is wiring checked by build and by Task 8. Accepted. |
| 6 | own text | Agrees. |
| 7 | own text | Agrees. |
| 8 | own text | Agrees. |
| 9 | own text | Agrees. |

## Log
