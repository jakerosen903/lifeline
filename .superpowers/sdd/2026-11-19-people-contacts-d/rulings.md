# PC-d rulings

- **D1.** Ruling: `MentionOut.init` keeps the argument `likelyAliasOfPersonID`, with a default of nil; the schema and the prompt drop the key, and the decoder ignores it — the plan's removal would touch about ten call sites for no gain — if wrong, a later commit removes a dead argument.
- **D2.** Ruling: when the app does not build after Task 4 because of the chip id, the change to `WhoIsThisViewModel` moves from Task 5 into Task 4 — each task must leave the app building — if wrong, one file is reviewed a task early.
