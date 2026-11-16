# Rulings — plan: docs/plans/2026-11-16-timeline-spine.md

Each ruling: what was decided, why, and what it costs if it is wrong.

R1 (Task 2, pre-flight). A gap is measured from the latest end of all the stops above, not only the stop directly above. Why: the spec says "from the end of an earlier range". With 2000–10, then 2003, then 2012, the stop directly above gives "9 years" and a dashed spine across years that the first moment covers. The latest end gives 2 years. Review Focus 2 names "a range inside a range" and the plan has no test for it, so one test is added: `aRangeInsideARangeDoesNotMakeAGapAfterIt`. Cost if wrong: one line in `SpineLayout.stops` and one test.

R2 (Task 2, pre-flight). `showsYears` is false only when the stop above shows the same years and the same qualifier. Why: with a stated 2001 above an inferred 2001, the second row would lose its margin, and "around" would show nowhere (its `rowDateText` is nil). PRINCIPLES 5 and the spec ("An uncertain date has its own mark and its own words") need the word. The plan's test `theSameYearIsWrittenOnce` holds unchanged. One test is added: `aGuessInTheSameYearKeepsItsWords`. Cost if wrong: one comparison and one test.

R3 (Task 2, pre-flight). A stop's period comes from the start of its shown years (decision 7), and `periodAbove` is set when that period differs from the period of the stop directly above. Why: the plan's rule, stated here because R1 makes the gap look further back and the period must not. Cost if wrong: none; this is the plan as written.

Owner's answer on the 12 decisions (2026-11-16): "Yes, go on" to the builder's proposal: change decisions 4 and 8, keep the other ten, with 2 and 9 as planned.

R4 (owner, decision 4). For a confirmed relation the margin shows no years and no qualifier; `showsYears` is false and `rowDateText` is the relation text. The stop below a relation compares its years with nothing: it always shows its years. Why: TimeRange says the far edge of a relation's band is the builder's slack and is never shown as a fact. Cost if wrong: one branch in `SpineLayout` and one test.

R5 (owner, decision 8). `SpineLayout.storyRange(members:)` gives a story's range for layout only: the span over the dated members; when that span is one year and every dated member reads as said, it is that year as stated, so the mark is a solid dot; otherwise the derived span, so one year is a dashed dot with "around". It is never stored. Cost if wrong: one function and its tests.

R6 (Tasks 4 and 5). One implementer does Tasks 4 and 5 on one build cycle, as the plan's Task 4 Step 1 allows. Two commits if each compiles, else one, and the ledger says which.
