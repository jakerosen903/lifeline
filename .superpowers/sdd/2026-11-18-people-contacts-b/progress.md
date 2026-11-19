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
