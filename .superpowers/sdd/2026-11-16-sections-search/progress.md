# SDD ledger — plan: docs/plans/2026-11-16-sections-search.md

Spec: docs/specs/2026-11-15-five-sections.md ("Shell", build-order step 8). Worktree /Users/jakerosen/dev/lifeline/lifeline-search, branch sections-search, base origin/main 42eb2bd. Simulator "Lifeline Search" 5CF768C4-64CD-40BE-9518-B61491B6FD70 (iOS 26.3).

Owner, 2026-11-19: "No need for approval on the plan. Just execute with your recommendations." Nothing is pushed without the owner's word.

## Pre-flight (2026-11-19)
An audit compared the plan (written at a1638c3) with 42eb2bd. 19 mismatches; all corrected in the plan, commit 96a79c1. No conflict left open between plan and spec.

## Tasks
Task 1: complete (commits c52b4fa..40b52e3, review clean). Minor, noted for the final review: a keycap emoji counts as a word; no test for a full-width apostrophe.
Task 2: complete (commits 40b52e3..0e35754, review clean). Minors for the final fix wave: matchedText can pick a telling that holds only the word the title already covers (prefer a text with a word the title lacks); the matchedText doc comment; no test for kind .other, feeling or goal; a comment on the force-unwraps in Search.swift. Check at Task 6: a fact whose quote holds every query word shows no second line.
Task 3: complete (commits 0e35754..4ccc9e1, review clean). Minors for the final fix wave: a test that a token of several words ("in-law") is marked whole; a test that every .text hit of Search.run has a snippet line. For Task 6: the snippet can hold a line break; the row must not let it break the layout.
Task 4: complete (commits 4ccc9e1..20266b2, review clean; privacy risks checked by the reviewer against the reused reads). Minors for the final fix wave: a test with two kept memories on disjoint spans of one segment (and make aSegmentWithNoKeptMemoryIsNotInTheIndex able to fail); a comment that words of one segment do not overlap in time. Known cost: the seven reads are not one snapshot; the index reloads on appear.
Task 5: complete (commits 20266b2..15546c8, review clean, built under ruling R4). Folded into Task 6's dispatch: leaving search in one step (R5), the Search button's 44 pt size measured in a test, the seed fails loudly when Lena is missing. Minors for the final wave: a wait before reading .value in the alias test. Known: YouUITests.testAPlayErrorLeavesAnOpenUndoInPlace fails on this tree with and without Task 5 (implementer's stash run); controller to check against main.
