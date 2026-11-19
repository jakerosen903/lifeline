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
- Task 3: implemented (commit follows), awaiting review. Rulings D6-D8.
