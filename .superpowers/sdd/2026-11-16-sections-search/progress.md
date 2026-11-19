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
Task 6: complete (commits 260a19f..aa650ff, review clean). For the final fix wave: the delayed pop becomes `.task(id: isActive)` so SwiftUI cancels it, and it must not wait when the keyboard is up if an immediate pop works; the Search button's tint and pressed look under .buttonStyle(.plain); a test with a line break in a snippet. Device check: "X" closes search in one tap after Return; VoiceOver says "Nothing found" once.
Final review (opus, 42eb2bd..d5d35f6): ready after fixes. 3 Important (folding on each keystroke, the uncancelled pop, the announcement on every keystroke), 10 Minor; report in final-review.md. One fix agent dispatched with the whole list.
Item 13 checked by the controller: YouUITests.testAPlayErrorLeavesAnOpenUndoInPlace also fails alone on main's code (lifeline-strip at c332fdb, same tree as 42eb2bd): "you.undo" not found. Not caused by search.
Fix wave: commits d5d35f6..6f9b6a1 (039ec7a kit, 7f41186 app, 6f9b6a1 test). Re-review (opus): clean; every Important fixed; residual Minors A (a pop can be armed while search is hidden), B (the "why found" line for facts, feelings, goals), C (a stale doc comment), D (an allocation per keystroke, parked).
Main merged locally: 0ab97da (people and contacts, v15). Kit on the merged tree: 1468 tests pass. An audit of search against people and contacts is running; its fixes are a merge adaptation, and residuals A to C ride with it.
Task 7 and merge fixes: commits 15ca706..ddfe58d (197345c own words, d409618 residuals A to C, ddfe58d docs). Scoped review (opus): code clean; docs needed text fixes (one Important: one letter also finds moment titles), corrected by the controller. Parked Minor: the test helper headingHoldsEveryWord reads the title when a cleaned quote is empty; no fixture reaches it.
Whole UI suite on the merged tree (at ddfe58d; dffd811 after it changes docs only): Executed 254 tests, with 0 failures, simulator "Lifeline Search". Kit on the same tree: 1470 tests pass (one timing test failed under load and passed alone).
Ledger closed 2026-11-19. Nothing pushed. The device checklist is not run.
