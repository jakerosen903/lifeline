# SDD ledger — plan: docs/plans/2026-10-23-m4.1-same-story-and-when.md
(Reconstructed 2026-10-23 from the executing session's transcript; the original file was not on disk in this checkout.)
Spec read: docs/specs/2026-10-23-m4.1-same-story-and-when.md
Pre-flight:
- T1→T2: EmbeddingRepository API (upsert/vector/all/delete/memoryIDsWithRows) consumed by MemoryMatcher — consistent.
- T1→T4: MemorySpan.titleText/candidateID, insertSpan/deleteSpans/nextSpanOrder/spans(in:)/updateFields consumed by merge — consistent.
- T2→T3: MemoryMatcher.related(to:excluding:) consumed by ExtractionQueue.packet — consistent.
- T2→T4/T6: index(_:), suggestion(for:extractorSameAs:), picker(for:excluding:includeHidden:) — consistent.
- T4→T6/T7: MergeReceipt, mergeCandidate, merge, unmerge, Error cases — consistent.
- T5→T7: TimeRange.stated(...), setStatedRange — consistent.
- T6→T7: SameAsPicker, UndoNotice — consistent. T7→T8: MemoryRowActions.addDate — consistent.
Task 1: complete (commits ddd43d9..c9b55bd, tests: sh -c 'cd ios/LifelineKit && swift test 2>&1 | tail -3' → ✔ Test run with 297 tests in 2 suites passed after 3.533 seconds.)
Task 2: complete (commits c9b55bd..d952e47, tests: sh -c 'cd ios/LifelineKit && swift test 2>&1 | tail -1' → ✔ Test run with 302 tests in 2 suites passed after 2.208 seconds.)
Task 3: complete (commits d952e47..1a47051, tests: sh -c 'cd ios/LifelineKit && swift test 2>&1 | tail -1' → ✔ Test run with 307 tests in 2 suites passed after 2.225 seconds.)
Task 4: complete (commits 1a47051..e8500d3, tests: sh -c 'cd ios/LifelineKit && swift test 2>&1 | tail -1' → ✔ Test run with 319 tests in 2 suites passed after 2.272 seconds.)
Task 5: complete (commits e8500d3..876924f, tests: sh -c 'cd ios/LifelineKit && swift test 2>&1 | tail -1' → ✔ Test run with 324 tests in 2 suites passed after 2.270 seconds.)
Task 6: complete (commits 876924f..29d108c, tests: sh -c 'cd ios/LifelineKit && swift test 2>&1 | tail -1' → ✔ Test run with 325 tests in 2 suites passed after 2.259 seconds.)
Task 7: complete (commits 29d108c..f259888, tests: sh -c 'cd ios/LifelineKit && swift test 2>&1 | tail -1' → ✔ Test run with 325 tests in 2 suites passed after 2.276 seconds.)
Task 8: complete (commits f259888..e304b26, shelf rows inline actions; kit suite green)
Task 9: complete (commits e304b26..8ee4b9d, decisions entry; device checklist pending — phone unavailable)
Final review: fresh reviewer (fable). 1 Critical, 4 Important, 10 Minor. Re-graded by effect: all five stand.
Final: Ruling: thresholds 0.55/0.80 untested on real voices — tuned on the owner's recordings per spec — cost if wrong: wrong suggestions the person must decline
Final: Ruling: a hidden memory can still be retrieved into the extractor packet — spec call #5 draws the line at excluded; hidden is about browsing, not the model — cost if wrong: the model sees a title the person hid from the timeline
Final: Ruling: "1996–99" stays (one display convention) — owner may overturn — cost if wrong: a copy change
Final: Ruling: a stand-in may be suggested on a card — spec call #3; mergeCandidate makes it real — cost if wrong: none seen
Final: Ruling: Undo after a collection in the snapshot was deleted fails loudly ("can't be undone") — acceptable, not silent — cost if wrong: one lost undo
Final: Ruling: the extractor may name a current-session memory from the packet — the person confirms — cost if wrong: a merge the person declines
Final: Ruling: device checklist waits on the owner (phone unavailable at the time) — owner's step
Final: minor (deferred): suggestion(for:) mutates the handler cache during view body evaluation (CardStack.swift:24)
Final: minor (deferred): CardStack plausibility test uses MatchConfig.default rather than the matcher's config
Final: minor (deferred): prompt v4 adds "they are the usual answer when the person is retelling" beyond the spec's sentence
Final: minor (deferred): the Change sheet's Undo has no 6 s window while the sheet is open
Final: minor (deferred): dead `if tellingWhen { }` in MemoryScreen's refine onDismiss
Final: minor (deferred): TimelineViewModel question loop filters on isConfirmed, not isSettled (cosmetic)
Final: minor (deferred): HashingEmbedder comment and Task 6 ledger call it a device fallback; live() does not wire it that way (correct); wording to fix
Final: minor (deferred): memory screen plays each telling on its own tap, not in order
Final: minor (deferred): Tell me when disables Save (with the hint) rather than the age row itself
Final: minor (deferred): acceptMemory's order-0 span has candidateID nil while merged spans set it
Final: fixed merge into a stand-in hid the story — mergingIntoAStandInMakesItReal + mergingAStandInSourceThrowsAndPickerSkipsStandIns RED→GREEN, suite 331/331
Final: fixed mergeCandidate was several transactions — mergeSpanIsOneTransaction RED→GREEN (MemoryRepository.mergeSpan), suite 331/331
Final: fixed backfill on the main actor and NLEmbedding loaded per sentence — nlEmbedderLoadsItsModelOnce RED→GREEN; backfill now Task.detached(.utility), suite 331/331
Final: fixed unmerge staleness counted spans only — unmergeAfterARenameIsRefused RED→GREEN (receipt.after snapshot compared), suite 331/331
Final: fixed scored() N+1 — memoriesWithVectorsIsOneQueryAndSkipsExcluded RED→GREEN (one join, excluded filtered in SQL), suite 331/331
Review fixes committed as 95fc1aa.
