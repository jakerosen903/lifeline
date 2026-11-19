# Rulings — plan: docs/plans/2026-11-16-sections-search.md

R1. Store changes are read-only additions (allAliases, tellingWords), not "SearchReads.swift only" — repositories keep their database private — cost if wrong: two more public reads to maintain.
R2. An alias whose fold equals the title's is dropped from the index — insertPerson writes one for every person — cost if wrong: none seen; an old spelling still finds the person.
R3. A fact, feeling or goal sorts by when it was told; a half-dated moment shows no date line — a stored range no screen shows must not show through search (non-negotiable 3) — cost if wrong: order of facts in "Memories" differs from an entity page.
