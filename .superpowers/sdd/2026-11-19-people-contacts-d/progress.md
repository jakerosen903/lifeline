# SDD ledger — plan: docs/plans/2026-11-19-people-contacts-d.md

Branch `people-contacts-d`, cut from `people-contacts-b` (8c882a9, PR #35). Spec: `docs/specs/2026-11-18-people-contacts.md`, "Step 2".
The owner said "Yes, build both" (PC-d, then PC-c) on 2026-11-19, without a review of each plan decision.

## Pre-flight scan

| Tasks | Produces against consumes | Found |
| --- | --- | --- |
| 1 | Tests against code | The plan removes the init argument `likelyAliasOfPersonID`; about ten call sites build `MentionOut` with it. Ruling D1. |
| 1 and 3 | Validator rejects a memory with an unknown handle; `HandleResolve` reads handles | Agree. The owner's entry is removed in Task 3, after validation, and the memory stays. |
| 1 and 2 | `MemoryOut.handlePeople` (1); `CandidateRepository.handlePeople(inSession:before:)` reads it (2); written by Task 3 | Task 2's tests build cards with `handlePeople` by hand. No conflict. |
| 2 and 3 | Packet reads cards; queue writes them | Agree. |
| 3 | `ValidatedOutput` is a stand-in name | The implementer uses the validator's real return type. |
| 4 and 5 | `PreviewChip.id` becomes `ChoiceKey` (4); the app's `WhoIsThisViewModel` passes the handle (5) | The app must build after Task 4. Ruling D2. |
| 4 and 6 | Keep by handle; scripted service gives handles | Agree. The queue runs `HandleResolve` for every service. |
| 7 | Needs `ANTHROPIC_API_KEY` | The plan says what to do with no key. |
| 8 | PR, then the default after the owner's yes | Agree with decision 2. |
| 2, 5, 6, 7, 8 | Own text | Each agrees with itself. |

## Progress

- Task 1: complete (commits 699757b..1fdbd7d, review clean). Minor, parked for the final review: a handle is compared untrimmed; `schemaStaysUnderTheUnionLimit` still asserts 12 (count is 11); a mention's `handle` is not checked against `people` (Task 3 must tolerate an unknown one); the app target was not built in Task 1 (build it by Task 4).
- Task 2: complete (commits c7b0c3d..bd9bf18, review clean). Minor, parked for the final review: the continuation test covers the superseded status only, not the "continues" marker; a first person id that the packet filter cuts hides a later valid one (D5). A second timing flake seen once under load: `CascadeVoiceSessionTests.interruptionClosesOpenSegment`.
- Task 3: complete (commits 08a49c9..d280ae9, review clean). Minor, parked for the final review: a continuation does not add a person id to a handle the earlier card already holds with none; no test for a continuation whose earlier card was kept. Carried to Task 4: Keep must take each handle once across a card and its continuation rows (D8).
- Task 4: minor (deferred): no direct test that `taken` from the recording gives two cards' same-name handles two persons.
- Task 4: minor (deferred): `handlesKept` drops the handles when the Same story target has no order-0 span.
- Task 4: minor (deferred): two functions named `handleLink`, one with a double optional; the handle-to-entity mapping is copied twice; `carried` reads awkwardly.
- Task 4: open for Task 5 or the final review: `separateTelling` finds a telling's people by said name, not by handle.
- Task 4: fix round 1/5 (1 addressed, 0 open — a stored choice for one handle is taken from the other handles of that name, in either order; commits 2b82afd..702a408)
- Task 4: complete (commits 2f83fca..702a408, review clean after one fix round). Rulings D9 to D16.
- Task 5: complete (commits 017742a..e658e00, review clean). Rulings D18 to D21.
- Task 5: minor (deferred): separating a telling can drop a person that a staying telling also named under another handle (owner-settled across tellings); `about.ref == handle` compares the ref untrimmed in a move; the doc comment of `group(of:)` does not name the mixed case (R-5a).
- Task 5 review, out of its diff, Important: a later segment that means a person of the recording without saying a name (a handle with no `people` entry) is rejected by the validator, or its fact gets no detail on Keep. Ruling D17: Task 4b, brief `task-4b-brief.md`.
- Task 4b: complete (commits c858ef5..214e370, review clean). Rulings D22 to D24.
- Task 4b: minor (deferred): no queue test for an output with `about_ref` only; the doc comment of `mayFollowAHandle` does not say why the wide gate is safe (D15).
- Task 4b review, Minor that needs a ruling: a fact with only `about_ref` = a handle, kept before or without the card that named the person, gets no detail and no sign. Ruling D22; the change rides with Task 6.
- Task 6: complete (commits d5c0da8..09f7087, review clean; includes D22). Open: its UI tests are built and NOT run (the simulator was held by the PR #35 suite). To run: `PeopleGuessUITests` (with the new `testTwoPeopleWithOneNameGetTwoChips`), `PeopleContactsUITests`, `LandingUITests`, `ExtractionUITests`, `FollowUpUITests`, `EntityPageUITests`, `KindsUITests`, `InterviewerUITests`; watch for a changed origin or chip of an on-file person that the sample script names.
- Task 6: minor (deferred): "the naming card is never kept" has no test of its own; no kit test that the scripted Maya card links an on-file Maya.
- Task 7: complete (commits 09f7087..61f3fd3, review clean). Open: the comparison is NOT run (no key in the build environment); the doc gives the owner the command; about 140 model calls, not 60. Rulings D26, D27.
- Task 7: minor (deferred): the handle assertion checks the pipeline, not the model; `HandleTally.says` does not join "the other Robyn" to a handle named "Robyn"; `people_refs` is checked against the recording so far also for `v6`.
- Task 7 review, out of its diff, Important: a person named in a segment that gives no memory card does not reach the next segment's `recordingPeople`. Ruling D25: Task 7b, with the comparison's table written row by row.
