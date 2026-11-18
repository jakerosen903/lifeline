# Rulings — plan: docs/plans/2026-11-16-timeline-spine.md

Each ruling: what was decided, why, and what it costs if it is wrong.

R1 (Task 2, pre-flight). A gap is measured from the latest end of all the stops above, not only the stop directly above. Why: the spec says "from the end of an earlier range". With 2000–10, then 2003, then 2012, the stop directly above gives "9 years" and a dashed spine across years that the first moment covers. The latest end gives 2 years. Review Focus 2 names "a range inside a range" and the plan has no test for it, so one test is added: `aRangeInsideARangeDoesNotMakeAGapAfterIt`. Cost if wrong: one line in `SpineLayout.stops` and one test.

R2 (Task 2, pre-flight). `showsYears` is false only when the stop above shows the same years and the same qualifier. Why: with a stated 2001 above an inferred 2001, the second row would lose its margin, and "around" would show nowhere (its `rowDateText` is nil). PRINCIPLES 5 and the spec ("An uncertain date has its own mark and its own words") need the word. The plan's test `theSameYearIsWrittenOnce` holds unchanged. One test is added: `aGuessInTheSameYearKeepsItsWords`. Cost if wrong: one comparison and one test.

R3 (Task 2, pre-flight). A stop's period comes from the start of its shown years (decision 7), and `periodAbove` is set when that period differs from the period of the stop directly above. Why: the plan's rule, stated here because R1 makes the gap look further back and the period must not. Cost if wrong: none; this is the plan as written.

Owner's answer on the 12 decisions (2026-11-16): "Yes, go on" to the builder's proposal: change decisions 4 and 8, keep the other ten, with 2 and 9 as planned.

R4 (owner, decision 4). For a confirmed relation the margin shows no years and no qualifier; `showsYears` is false and `rowDateText` is the relation text. The stop below a relation compares its years with nothing: it always shows its years. Why: TimeRange says the far edge of a relation's band is the builder's slack and is never shown as a fact. Cost if wrong: one branch in `SpineLayout` and one test.

R5 (owner, decision 8). `SpineLayout.storyRange(members:)` gives a story's range for layout only: the span over the dated members; when that span is one year and every dated member reads as said, it is that year as stated, so the mark is a solid dot; otherwise the derived span, so one year is a dashed dot with "around". It is never stored. Cost if wrong: one function and its tests.

R6 (Tasks 4 and 5). One implementer does Tasks 4 and 5 on one build cycle, as the plan's Task 4 Step 1 allows. Two commits if each compiles, else one, and the ledger says which.

R7 (Task 5, review). When an open story is the last stop, the spine continues beside its members and ends at the bottom of the last member. Why: the Task 5 edge case and device check 10 say "the spine continues beside them"; "the last row's line ends at its mark" is the general rule and the open story is the named exception. Cost if wrong: one condition in `SpineRowView`.

R8 (Task 5, review). A spine row shows the age text ("age ~7") on its date line also when the margin holds the years. Why: before this PR the age was visible on the row; it says why the guess is where it is (PRINCIPLES 5). The plan does not mention it, so it must not vanish. Cost if wrong: one line of layout.

R9 (Task 5, review). On a spine row the "in your voice" length sits on its own line under the people line, at every text size, so the title has the full width. Why: with the margin in place, most two-word titles wrapped beside the length. The spec keeps the length; it does not say where. Shelf and collection rows do not change. Cost if wrong: layout only.

R10 (Task 5, review). At accessibility sizes a story row also shows its date above its title: the brief says "for every row".

Withdrawn by the builder: "the solid dot must be filled" and "stated years must not be ochre". The owner's mock-up `TL_SpineStrip` draws every mark as a ring (solid or dashed border) and every margin year in ochre text. The code matches the mock-up.

Not fixed, for "After S6a": the shelf header counts a half-open moment ("before 2004") as "undated"; a story member that is also in a collection shows in both and is counted twice (as before this PR).

R11 (Task 6, review, plan-mandated). `testAtTheLargestTextTheDateSitsAboveTheTitle` stays as the plan wrote it, though its label assertion holds at every text size. Why: the row's label is the same at every size by decision 12, so XCUITest cannot tell where the date is drawn; the test still proves the row is reachable and hittable at the largest size. Where the date sits is checked by Task 7's screenshot and by device check 7. Cost if wrong: a layout regression at the largest size is caught on the device, not in CI.

R12 (Task 6, review, plan-mandated). `testEveryPlacedMomentIsOnTheSpine` stays as written, though it also passes on the build before the spine. Why: it is a guard for Review Focus 3 ("Nothing vanished"); a guard for kept behaviour passes before and after by design.

R13 (Tasks 4+5, fix round 2). Opening a story scrolls it to the top of the list, on the spine and on the shelf. Why: on the spine a story sits higher than before, and its opened members landed under the record bar and the tab bar; `testMemoryScreenPlaysAndShowsEvidence` then tapped the tab bar. The test must not change (only three named assertions move), and members that open under the bars are a defect for a person too. Cost if wrong: the list moves when a story opens; to overrule, remove the scroll and move the test's swipe. Flagged for the owner in the final report.

R14 (Tasks 4+5, fix round 2). `CheckThisTag` (in `Cards/MemoryCard.swift`, outside the plan's file list) wraps in place of a fixed size. Why: a long tag ("Check this: sometime between 1993–98?") made a member row wider than its cell and clipped the "…" menu. The spine's margin made the column narrower, so this PR exposed it. Cost if wrong: one modifier.

R15 (Tasks 4+5, fix round 2 re-review). The chapter tag and the Check-this tags inside a row do not open the memory when tapped; the row's text block, full width, does. Why: the tags must stay their own accessibility elements (Task 6 counts `timeline.tag`; an existing test reads `card.checkThis`), and S6c makes the tag a button of its own. Cost if wrong: a tap on a tag does nothing until S6c.

R16 (Tasks 4+5, fix round 2 re-review). An open story's members go back to list rows of their own on the spine, as on the shelf. The `ViewThatFits` change to off-spine titles comes out. Why: neither was needed for the finding. Several context menus (Hide, Exclude, Delete) in one list cell can lift the wrong member; the title change alters every shelf and collection row, outside this PR.

R17 (final review, Important 1). The qualifier "around" is also set for a capsule when the date text is "around {years}" (an age guess that crosses two calendar years, "around 1999–2000"). Why: without it the margin showed "1999–2000" with no word and the row showed no text, the same as a stated range (PRINCIPLES 5, decision 4). Cost if wrong: one condition and one test.

R18 (final review, Important 2). A gap that is measured from or to the band of a confirmed relation has no label and is not dashed; its length is kept. Why: the edge of that band is the builder's slack (R4), so "9 years" would state a number the person never gave. The waypoint above a relation still comes from the start of its band; that cost is recorded in "After S6a". Cost if wrong: one condition and two tests.

R19 (final review). The first full UI run was stopped when the final review asked for kit and view fixes. The one full UI run is made after the fix wave, on the final code.

Owner, 2026-11-16, on R13: "Keep it". The scroll on story open stays.
