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
- Task 1: complete (commits 84771d2..79d317b, review clean). Kit 1307 pass. Ruling PB4. ⚠️ item checked by the controller: `MatchKey.of` folds runs of whitespace to one space, so the word split in `ContactSearch` holds; a hyphenated name ("Anne-Marie") is one word, so "marie" does not find it.
- Task 1: minor (deferred): `ScriptedContactsDirectory.cards(identifiers:)` and `picture(identifier:)` ignore the access status, so a "denied, then link" test could pass against the script when the real directory would fail (Task 4's denied test must set this up with care); no search test for a family-name prefix or an empty full name; a hyphenated second name is not found by search.
- Task 2: implemented (commit db28c3c). Kit 1322 (one timing flake passed alone), app builds. Review needs fixes — 2 Critical (a rename saves the contact's name as an alias; an entity curiosity question carries the contact's name to the model), 1 Important (the no-contact-name test builds the packet by hand), Minor 4 taken into the round (merge by contact identifier). Rulings PB10 to PB13.
- Task 2: fix round 1/5 (6 addressed — rename keeps no contact name; one helper names a person for the model, used by the packet, curiosity and the interviewer's opening; real-path packet test; merge by contact identifier; the contact line only in the person's first recording; VoiceOver label; commit 8c624fe). Kit 1330 (one known flake passed alone), app builds. Rulings PB14, PB15.
- Task 2: complete (commits 79d317b..8c624fe, review clean after fix round 1).
- Task 2: minor (deferred): each fetched link row runs a correlated first-session subquery (slow for a person with hundreds of links); a person page's subject has no model title before its first refresh; `known()` is read outside Keep's write transaction, so a concurrent link of the same contact gives an index error, not a refusal.
- Task 2: to carry into Task 6: `PersonLinkWrites` "Someone new" falls back to `link.person.displayName` with `nameOrigin: .said` when a link has no said name; for a person from a contact that would make the contact's name a said name. Task 6 must close it (use the name for the model, or refuse the fallback).
- Task 3: implemented (commit 7fda3d4). Kit 1347 (two known flakes passed alone), app builds. Rulings PB16 to PB18; PB19 (controller) sends one change to Task 4.
- Task 3: review needs fixes — 1 Important (the photo insert and the contact_photo_id record were two transactions). Fix round 1/5 (5 addressed — one transaction with a test for the window; unlink clears the guess flag (PB19); a shared copy survives a relink; PNG and HEIC pictures; Undo keeps the stored role; commit 0bd8b9d). Kit 1350 pass, app builds. Rulings PB20, PB21.
- Task 3: complete (commits 8c624fe..0bd8b9d, review clean after fix round 1).
- Task 3: minor (deferred): no test for the guard-failure branch of the picture copy (the person is relinked during the copy); the owner can re-add the copy's exact bytes and not know it is still the app's copy; the store layer throws `ContactLinkActions.Error`; `PeopleRepository.db` and `PhotoRepository.deleteIfHomeless` went internal.
- Task 4: implemented (commit c822251). 35 new tests; kit 1385 (one known flake passed alone); app builds. Rulings PB22 to PB26.
- Task 4: review needs fixes — 1 Important (a name re-link under limited access can pick a namesake and replace the picture; ruled PB34), minors taken into the round (reguess respects a decline, PB35; trim the stored contact name; wording of PB22 to PB24; spec line on 'assumed or new'). The round waits for Task 5's implementer to finish, because both edit the kit's Contacts files.
- Note: the UI suite on the main merge (b55c02f) did not finish: 104 passed, then the run was cut off when a later build used the same simulator. Three failed before that, all from main's photo work: PhotoCardUITests.testRemoveTakesThePhotoOffOneMemory, PhotoCardUITests.testUseThisDateDatesTheMemory, PhotoStoryStartUITests.testCancellingWhileThePhotoIsAddedStoresNothing. Not yet known whether they are load flakes or a merge interaction. Task 8 must run these three alone and then the whole suite.
- Task 5: implemented (commit af49e1e). Kit 1396 (one timing flake passed alone), app builds, LandingUITests and PeopleGuessUITests 27 pass (one runner restart, passed alone). Rulings PB27 to PB33.
- Task 5: review needs fixes — 1 Important (one log line prints an error's full text), minors taken into the round (flag set after the answer; no prompt after a heavy landing; chip contact lines worked out off the render path). Rulings PB36, PB37.
- Task 4: fix round 1/5 (6 addressed — missing stays missing under limited access (PB34); a declined contact is never linked by reguess (PB35); trimmed kept name; ruling wording; no write when unchanged; the spec line narrowed; commit 38aeab5). Kit 1401 (two known flakes passed alone), app builds.
- Task 4: complete (commits 0bd8b9d..38aeab5, review clean after fix round 1).
- Task 4: minor (deferred): when two contacts fit and one is declined, reguess links nothing, while the suggestion would offer the other (the conservative reading of PB35 stands); a row with a null kept name and a card with an empty full name is written at every launch; no test for missing-to-linked under limited access.
- Task 5: fix round 1/5 (5 addressed — the log prints the error's type only; the asked flag is set after the answer; no prompt on a heavy landing or while sorting runs (PB36, PB38); chip lines worked out off the render; commit 1f496ea). Chip and prompt kit tests pass, app builds, LandingUITests 14/14. Ruling PB38; the task 4 fixer's trimming ruling is renumbered PB39.
- Task 5: complete (commits 38aeab5..1f496ea with af49e1e, review clean after fix round 1).
- Task 5: minor (deferred): the chip row's task id holds the cache's count, not its content, so a "New" chip's contacts line can be stale after a rename; `access()` is read in `body` each render; an open person page does not follow an access change until its next refresh; the prompt can show on a landing resumed at launch (still that recording's landing); the full kit suite was not rerun after the fix round (Task 6 runs it).
- Task 6: implemented (commit ef43f9d). 15 new tests; kit 1417 (two known flakes passed alone); app builds; PeopleGuessUITests 14/14. Rulings PB40 to PB45.
- Task 6: complete (commit ef43f9d, review clean). ⚠️ items checked by the controller: `ContactsAccessPrompt.ask()` awaits the cache refresh before it returns; Keep runs on the main actor, but the look-again after access (`reguess`) writes from a detached task, so a Keep pressed in that second could read before and write after it and hit the unique index (the Keep fails and can be pressed again; noted for the final review).
- Task 6: minor (deferred, final wave candidates): (a) a card with a guessed ref and a stored contact choice for the same contact keeps `created_by_guess` true on a person the owner chose (PersonGuessOnKeep ~594) — fix before merge; (b) the PB42 refusal shows the stale-undo sentence, which is false there; (c) a held contact picked in search shows as a second row when its person is already listed; (d) the sheet's contact rows are not rebuilt after access is given in the sheet; (e) "In a story as {name}" and `who.settings` are new copy and a new identifier, for the owner's sign-off; (f) no kit test for a whole-group move to a contact or two moves to one contact back to back; (g) two quick taps on "Search your contacts" can start two asks.
- Task 7: implemented (commit f8c70fa). 9 new kit tests; kit 1426 pass; app builds; PeopleUITests 10/10, EntityPageUITests 8/8 (one assertion moved before a scroll). Rulings PB46 to PB49.
