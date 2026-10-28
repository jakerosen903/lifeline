# SDD ledger — plan: docs/plans/2026-10-25-m7-elements.md
Spec: docs/specs/2026-10-24-m7-elements.md (redlined 9c45282). Branch m7-elements from main d117590.
Ship order: PR A on m7a-kinds (A1–A4), PR B on m7b-entities stacked on m7a-kinds (B1–B10).
Execution: inline (executing-plans), resumed on Opus 5.5 after a usage limit.
Pre-flight:
- No plan-review skill installed; self-review per writing-plans done inline.
- A1→A2: Memory.kind / isMoment / aboutMemories(includingHidden:) produced in A1, consumed in A2. OK.
- A1→A3: CandidateActions.setKind(_:_:) produced in A1. OK.
- B1→B2: EntityRepository produced in B1; B2 consumes it. OK.
Baseline: 426 tests, SegmentPlayerTests.playStartsAtRangeStartAndStopsAtRangeEnd fails on main before any M7 change (AVAudioPlayer on this Mac's session; audio output), not touched by M7.
Task A1: Ruling: a non-moment's relative anchor still makes a resolver stand-in (floating target) — that is placement machinery, not a question; only the curiosity draft is dropped — cost if wrong: a stand-in title on the "waiting for a place" count.
Task A1: Ruling: Separate this telling keeps the original memory's kind (the person may have corrected it) rather than the telling card's — cost if wrong: one tap on What is this?.
Task A1: complete (commits cb09d68..8db1672, tests: swift test → 432 tests, only baseline SegmentPlayer failure)
Task A2: Ruling: About rows show title + quote with a "…" menu (Hide, Delete); no band, no inline Add a date; Memory screen shows the kind label in place of the range and hides evidence and the date Check-this tag — cost if wrong: copy/layout only.
Task A2: complete (commits 8db1672..34301c7, app build: BUILD SUCCEEDED)
Task A3: complete (commits 34301c7..6f8ceab, app build: BUILD SUCCEEDED)
Task A4: Ruling: About row's accessibility label sits on the label, not the Button — ignoring children on the Button removed its button trait — cost if wrong: none.
Task A4: complete (commits ..9a9b9f1, tests: swift test 433 (baseline SegmentPlayer only); KindsUITests TEST SUCCEEDED)
Task B1: Ruling: a migrated person or place keeps its id as its entity's id, and person.entity_id = id — one id per being, so every PersonID is also an EntityID — cost if wrong: a later split of the two ids is a migration.
Task B1: Ruling: in B1, v9b adds person.entity_id with alter table; B2 edits the (unshipped) v9b to rebuild person without display_name — keeps B1 green between tasks — cost if wrong: none, v9b has not shipped.
Task B1: note: BackupTests flake under a parallel run (exportedDatabaseMatchesTheSourceUnderConcurrentWrites, newerSchemaIsRefusedOlderIsMigrated: .partial move into ~/Documents); pass on rerun; pre-existing; tests write real files into the owner's ~/Documents.
Task B1: complete (commits 9a9b9f1..d2c5d6f, tests: swift test 436, baseline SegmentPlayer + Backup flake only)
Task B2: Ruling: Person/Place/MemoryPerson/MemoryPlace stay as Swift value types (public API unchanged for callers) but carry no table of their own: Person reads through Person.selectSQL (join entity), Place is built from an Entity, MemoryPerson/MemoryPlace expose .link: MomentEntity — fewer call-site changes, one storage path — cost if wrong: a later rename of the value types.
Task B2: Ruling: Snapshot.people/places became Snapshot.links: [MomentEntity] (details included); undo skips a link whose entity was deleted since — cost if wrong: none.
Task B2: Ruling: the owner's entity title mirrors profile.displayName exactly, "" included (ProfileRepositoryTests expects ""), the page labels it "You" — cost if wrong: copy.
Task B2: note: no "Same person" merge of two people exists in the kit; renameMergeDelete covers rename, Same story (memory merge) and undo, memory delete.
Task B2: complete (commits d2c5d6f..b05e551, tests: swift test 439, baseline only; app BUILD SUCCEEDED)
PR A fix: full UI run on m7a-kinds (worktree, while PR B continued): LandingUITests.testChangeTitleFromTheCard and SameStoryUITests.testChangeSheetMergesIntoAnotherMemory failed — the four-row "What is this?" section pushed later rows below the fold. Fixed in 3a4bfef (one Menu row at the bottom). Two other failures (testResumeAfterKillOpensTheLanding, testKeepSeparateNeverReturns: "Timed out while synthesizing event" / ~10-min runs) happened while the main tree was building in parallel — to recheck on a quiet simulator.
B branch rebased on m7a-kinds after the fix (B1 6c10075, B2 32b30cb).
Task B3+B4+B5: Ruling: done as one commit (ae92874) — the scripted service, queue and Keep path all needed the v6 types and the packet's entity section at once; B5's packet section is complete here (builder param, queue fill, budget dropper before people) — cost if wrong: a larger commit to review.
Task B3: Ruling: v6 puts idea titles on MentionOut.title (mentions are where ideas come from); the validator nils a non-verbatim title rather than rejecting the card; IdeaTitle.defaultTitle uses "d MMMM" en_GB ("25 October") — cost if wrong: copy.
Task B4: Ruling: a place/thing/idea mention that a memory in the same output carries (about_ref == ref, or named in entity_refs), or that is already on file, is stored accepted as a record; only an uncarried new one is a pending .entity card — "Keep includes what the card showed" — cost if wrong: a thing named only on a memory's chips gets no card of its own (by design).
Task B4: Ruling: an entity card's span is the first linked memory's primary span, else the whole segment (mentions carry no word span) — cost if wrong: a longer Play on the page.
Task B4: Ruling: about_ref is honored only for fact/feeling/goal; a moment's about_ref is ignored (it links by entity_refs as a mention) — cost if wrong: none.
Task B3/B4/B5: complete (commit ae92874, tests: swift test 454, baseline only; app BUILD SUCCEEDED)
Task B6: Ruling: a domain hint tags the memory it was heard on; an entity gets tags from its mention's domain_hint when kept, and from the page's Add a tag (B8); the Things screen filter reads entity tags — cost if wrong: one more tag path.
Task B6: complete (commit 5e8e9c9, tests: domainHintAcceptedTagsTheElement, notQuiteTagsNothing green; app BUILD SUCCEEDED)
Task B7: Ruling: a question closed because a moment arrived is stored answered; one the person dismissed is never made again; curiosity_item gains entity_id in v9b — cost if wrong: none.
Task B7: Ruling: person_without_moment fires for any person (not the owner) with no linked moment, since every person link is a moment mention — cost if wrong: a question about someone named only on a fact.
Task B7: complete (commit 1f644e2, tests: swift test 461, baseline only)
Task B8: Ruling: the People screen (Who's-this queue, rename) stays where it is; the entities screen's People segment lists the same people as entity pages — existing UI tests and the queue keep their place — cost if wrong: two ways into people.
Task B8: Ruling: "About you" is the owner's entity page, reached from the owner's details; not a separate tab (spec: left to the builder) — cost if wrong: one more entry point later.
Task B8: complete (commit 0c78a78, tests: spanTextSaysWhatIsKnown, anIdeasMomentsOrderByDate; app BUILD SUCCEEDED)
Task B9: Ruling: the non-moment filter for stories sits in StoryRepository.join, the one funnel for Keep, createStory, addToStory and groupPair — cost if wrong: a group of two facts returns a story that was deleted as empty.
Task B9: Ruling: PairFinder already pairs every visible memory, so details pair with no code change; detailsTakePartInPairs pins it — cost if wrong: a fact may be paired with a moment.
Task B9: complete (commit 4906b6f, tests: swift test 466, baseline only; app BUILD SUCCEEDED)
PR A recheck (3a4bfef, quiet sim): LandingUITests.testChangeTitleFromTheCard, testResumeAfterKillOpensTheLanding, OrganizeUITests.testKeepSeparateNeverReturns, SameStoryUITests.testChangeSheetMergesIntoAnotherMemory, SteadyUITests.testTrimMovesTheTellingToTheChosenWords all PASS. KindsUITests failed at openReview ("Transcript & memories" not found) while the main tree built in parallel — rerun pending.
PR A UI: KindsUITests PASS on 3a4bfef (quiet sim); TimelineUITests.testAddingABirthdayPlacesTheAgeMemory and testSessionsAreOneTapAway timed out once in a long run, PASS alone — simulator flakes. Every UI test has passed on PR A.
Task B10: Ruling: an entity's derived span is .stated only when every placed member is stated/confirmed, else .inferred (spec: 'with their uncertainty') — replaces ChapterRepository's .derived on entity pages — cost if wrong: copy ('in' vs 'around').
Task B10: Ruling: 'a place page shows its span' is pinned with a thing (the house); places share the code path — cost if wrong: none.
Task B10: fix: EntitiesScreen/EntityScreen hold their models in @State — NavigationLink destinations rebuilt them on every timeline refresh, resetting the segment and the tag filter.
Task B10: complete (commit 92e7985, tests: swift test 467, baseline only; EntitiesUITests 2/2 PASS)
PR B UI: full run 45 passed, 4 failed (session-screen timeouts); the 4 rerun alone all PASS. Every UI test (49) has passed on 92e7985.
DONE: all tasks A1–A4, B1–B10 complete. Nothing pushed.
