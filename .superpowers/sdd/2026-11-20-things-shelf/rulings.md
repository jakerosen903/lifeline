# Rulings — plan: docs/plans/2026-11-20-things-shelf.md

R1 (2026-11-20). S7 starts before the two-week watch in docs/plans/2026-11-15-sections.md ends. — Why: the owner said to continue with the next task, and was told of the rule. — Cost if wrong: the shelf is built before use of S2 to S6 could change it.
R2 (Task 2 review, 2026-11-20). `ThingQuote.choose` skips a detail that has no first telling, instead of treating it as safe. — Why: the heavy-session rule is a safety rule; when the app cannot tell which session a line came from, it must not show the line (it fails closed). A told detail always has a telling, so this hides nothing in a sound archive. — Cost if wrong: a detail with a missing telling row never gives a quote.
