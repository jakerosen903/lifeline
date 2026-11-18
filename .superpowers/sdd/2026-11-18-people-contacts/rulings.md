# Rulings — docs/plans/2026-11-18-people-contacts.md

- R1 (pre-flight): `candidate_person_choice.choice` holds `person`, `contact`, `new` or `not_a_person`.
- R2 (pre-flight): a memory's person links include the owner when the owner is linked. The plan said "never the owner"; today's memory page shows them.
- R3 (task 1): `Person` encodes all six new columns, so a `Person` round-trips through insert and update. Same pattern as `notes`: a stale `Person` value overwrites the contact fields on update. Callers that change only contact fields should use SQL, not a whole-record update.
- R4 (task 1): `LinkOrigin.stronger` treats nil as weaker than every case, including `new`.
- R5 (task 1): the v13 migration test now migrates `upTo: "v13"`, because v14 adds columns to `person` and `moment_entity` and the test compares whole rows. v14 has its own row-preservation test.
- R6 (after task 1 review): Task 3 also owns the four raw-SQL sites in `MemoryRepository` that copy a link with only `role_text`. Each must carry `origin` and `person_handle`, and on a key collision the surviving row keeps the stronger origin. Why: without it a memory merge or a kind change turns a marked guess into an unmarked link, which hides a guess (principle 5). Cost if wrong: Task 3 is larger.
