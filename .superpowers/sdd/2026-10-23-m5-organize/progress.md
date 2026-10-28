# SDD ledger — plan: docs/plans/2026-10-23-m5-organize.md
Spec: docs/specs/2026-10-23-m5-organize.md (read). Branch m5-organize from main 1235647.
Pre-flight:
- T1→T3/T7: StoryRepository.insert(title:chapterID:) produced; T7 consumes insert(id:title:chapterID:) — T7 says insert takes optional id; add `id: StoryID? = nil` in T1 so both hold. OK.
- T2→T4: MemoryOut.extraSpans/continuesCandidateID; T4 consumes the same names. OK.
- T2→T6: sameAsMemoryIDs [String]; T6 matcher takes [MemoryID]. Convert at call site. OK.
- T1→T5: DuplicatePair verdict PairVerdict defined in T1 Domain; T5 says ReconcilerOutput.swift defines PairVerdict — define once in Domain/DuplicatePair.swift (T1), T5 reuses. Ruling recorded.
- T5→T9: ReconcileService / DuplicatePass names consistent. OK.
- T6→T9: suggestions(for:extractorSameAs:) → CardHandler.suggestions(for:). OK.
Task 1: Ruling: PairVerdict lives in Domain/DuplicatePair.swift, not ReconcilerOutput.swift — one definition, T1 needs it first — cost if wrong: a file move.
Task 1: complete (commits f0f09d9..c15f9a9, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 343 tests in 2 suites passed after 2.402 seconds.)
Task 2: Ruling: ContextPacket.PendingEntry/StoryEntry and the pending/stories fields (empty defaults) land in Task 2, builder params in Task 3 — the scripted continuation reads packet.pending and Task 3 is where the queue fills it — cost if wrong: none, Task 3 extends the same types.
Task 2: complete (commits c15f9a9..5a06931, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 348 tests in 2 suites passed after 2.348 seconds.)
Task 3: complete (commits 5a06931..f503131, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 353 tests in 2 suites passed after 2.452 seconds.)
Task 4: complete (commits f503131..ac6c282, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 357 tests in 2 suites passed after 2.412 seconds.)
Task 5: Ruling: ScriptedReconcileService says same_moment when the two titles are equal ignoring case (not merely the same first word) — 'The canal' and 'The blue door' share a first word and must not merge in the fixture; the UI test's two cards are both 'The blue door' — cost if wrong: one scripted rule.
Task 5: Ruling: samePair's pair row cascades away with the folded (newer) memory, so there is no lasting .merged status; undoPair re-inserts the row as .open — the schema's cascade is right (a deleted memory must drop its pairs) and a merged pair cannot be found again because one side no longer exists — cost if wrong: PairStatus.merged is never stored.
Task 5: complete (commits ac6c282..c01adfa, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 367 tests in 2 suites passed after 2.724 seconds.)
Task 6: complete (commits c01adfa..612f07c, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 370 tests in 2 suites passed after 2.471 seconds.)
Task 7: Ruling: the queue remembers raw ref → minted StoryID for the life of the session's queue (not only within one output) — the scripted service and a model that echoes a raw ref across segments must land in one story — cost if wrong: a second story after a relaunch mid-session, fixable by also matching pending cards' refs (which it does).
Task 7: Ruling: mergeGroup orders by first telling, then real memories before stand-ins, then id — a stand-in that borrowed a span from the same session as a real memory must not win the tie and swallow it — cost if wrong: a group naming only a stand-in and a same-session memory is refused (.standIn) instead of promoted; the person can still Same story into it from the picker.
Final: minor (deferred): SessionRecorderTests.stopReturnsBeforeExtractionFinishes asserts elapsed < 500 ms and flakes under a full parallel suite run (seen 4× this branch, passes alone and on main); pre-existing, not touched by M5.
Task 7: complete (commits 612f07c..cebe826, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 377 tests in 2 suites passed after 2.598 seconds.)
Task 8: Ruling: mergeCandidate (Same story on a card) also carries the card's continuation spans and their edges, continuesOrder = the card's span order — the card shows '+ n segments' and Keep/Same story must include what the card shows; Task 4 only wired acceptMemory — cost if wrong: none, a card without extraSpans behaves as before.
Task 8: Ruling: on Separate, the original's range is cleared for re-derivation when it is not settled OR its evidenceText equals a leaving anchor's phrase — the resolver stamps an absolute anchor's year as origin .stated with the phrase as evidence, which 'a stated range stays' did not mean; Tell me when writes the bare year/'around N'/'A–B' — cost if wrong: an extractor phrase that is exactly a bare year could clear a Tell-me-when date of the same year; it re-derives from remaining anchors.
Final: minor (deferred): MemoryMatcherTests.aNilEmbedderWritesNothingAndSuggestsNothing orders two memories created with .now back to back; a tie under a loaded parallel run flips the order (seen once on this branch, 6/6 alone); pre-existing, picker untouched by M5.
Task 8: note: a SIGSEGV in ContextPacket.encode during two suite runs came from stale object files after a temporary checkout of main's kit sources for a flake comparison; swift package clean fixed it; no code change.
Task 8: complete (commits cebe826..035d2c7, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 380 tests in 2 suites passed after 2.477 seconds.)
Task 9: Ruling: under -uiTesting the duplicate pass also appends its log lines to <db dir>/duplicates.log — UI tests cannot see the app console and the pair flow could not be diagnosed otherwise — cost if wrong: a small file in the test sandbox, never in live.
Task 9: Ruling: both cards of a not-yet-kept story show "Part of a new story with: {other}"; an opted-out card no longer counts as the other — symmetric and honest; the spec names only the second card — cost if wrong: one extra line on the first card.
Task 9: Ruling: a continuation's Play on the memory screen plays the telling's first span then each continuation in turn (one row) — the owner's checklist says "the memory plays through" — cost if wrong: a short gap between parts.
Task 9: complete (commits 035d2c7..17a620a, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 381 tests in 2 suites passed after 4.213 seconds.)
Task 10: Ruling: a story with fewer than two visible members renders its member as a plain row (a group of one is not a group); the row count tests rely on it — cost if wrong: a one-member story is invisible as a story until a second member joins.
Task 10: note: three older UI tests (relative question, memory screen evidence, Change sheet merge) now open the story row first; the product change folded their rows.
Task 10: complete (commits 17a620a..1428f8a, tests: swift test --package-path ios/LifelineKit → ✔ Test run with 381 tests in 2 suites passed after 3.022 seconds.)
Task 11: complete (commits 1aec489..1428f8a, tests: swift build --package-path ios/LifelineKit → Build complete! (0.83 sec))
Final review: fresh reviewer (fable) on review-1235647..1428f8a.diff — 1 Critical, 7 Important, 12 Minor.
Final: fixed C1 undo loses pair decisions and story membership — undoRestoresPairDecisionsAndStoryMembership RED→GREEN (Snapshot carries pairs, story moment and title; restore saves every memory first then re-inserts them), suite 387/387 serial
Final: fixed I1 continuation hint cannot be accepted after Keep — continuationHintCanBeAcceptedAfterKeep RED→GREEN (acceptHint looks the memory up by created_from_candidate_id, no segment join)
Final: fixed I2 continuation after Keep had no Same-as — continuationAfterKeepIsASameAsCard RED→GREEN (queue prepends the kept memory's id to same_as_memory_ids)
Final: fixed I3 person named only in a continuation never linked — aPersonNamedOnlyInAContinuationIsLinkedWhenResolved RED→GREEN (names() scans continuation payloads; root cause also: setStatus wiped the "continues <id>" marker on Keep, now setStatusKeepingRejection)
Final: fixed I4 mergeGroup folded before validating the card — mergeGroupWithABadCardChangesNothing RED→GREEN (payload and span checked first)
Final: fixed I5 undo of One story detached the wrong memory — ungroupPairReversesExactlyWhatGroupingDid RED→GREEN (groupPair returns GroupedPair; ungroupPair reverses it; CardHandler uses it)
Final: fixed I6 Keep joined a story the card never showed — no kit test (CardHandler is app code): storyLine() records which cards rendered a line and keep() joins only those; covered by OrganizeUITests.testStoryLineOnTheCardAndOptOut and testStoryRowGroupsAndExpandsAndRenames
Final: fixed I7 story rows dropped members in a collection — no kit test (TimelineViewModel is app code): members are no longer excluded for being in a collection (builder call 6); covered by the Organize/SameStory UI runs
Final: Ruling: packet truncation drops the session's own memories before related ones (array order) and the per-table caps (people 50, curiosity 10) still apply before the budget — harmless at 6000 tokens; related memories are what a retelling needs most — cost if wrong: a 50+ memory session loses its oldest own memories from the packet first
Final: Ruling: "Keep separate" on a Sounds-like-one-story pair writes .separate, foreclosing a later same-moment ask of that pair — one question per pair keeps the card two taps wide (owner's call 2) — cost if wrong: a pair declined as "one story" is never offered as "same moment"
Final: Ruling: the resolver interplay when a confirmed range's anchor leaves on Separate is unverified — a confirmed range is settled and stays; the anchor moves — cost if wrong: a confirmed memory keeps a date whose evidence moved
Final: minor (deferred): DuplicatePass drops a requestRun made while a run is in flight (guard !running); add a rerun flag
Final: minor (deferred): fold does not carry the source's story membership to a target with none
Final: minor (deferred): separateTelling's "staying" set ignores the original card's continuations
Final: minor (deferred): continuation payload rewrite (updatePayload) sits outside insertAll's transaction
Final: minor (deferred): addToStory/splitStory are several transactions
Final: minor (deferred): openPairs fetches open(limit: 6) then filters hidden; six hidden pairs hide the rest
Final: minor (deferred): story-pair copy differs from spec ("One story"/"Keep separate" vs "Sounds like one story"/Keep/Not quite)
Final: minor (deferred): acceptStoryHint renames an already-titled story without saying so on the card
Final: minor (deferred): continuationSpans skips an unfit span silently while the card says "+ n segments"
Final: minor (deferred): isNamed substring match ("Al" matches "always") affects people ordering only
Final: minor (deferred): a group's folds and the card's span are not one transaction (validated first now, but a kill mid-way leaves partial folds)
