# Device check: search

No check on this list has been run yet.

The owner ticks each item on the iPhone. Each item is one check. Build and install the `sections-search` branch first. Plan: `docs/plans/2026-11-16-sections-search.md`. Decisions: `docs/DECISIONS.md`, entry "2026-11-19 · S5".

- [ ] 1. The Search button shows on all five tabs, in light and dark appearance, and with Reduce Transparency on.
- [ ] 2. The Search button is olive like "Sessions". It dims while you press it. It does not crowd "Sessions", "More" or "Settings".
- [ ] 3. The record bar shows on the search screen and reads "Tell a story". It names the page after you open a result.
- [ ] 4. With the keyboard up, the results scroll clear of the keyboard, and you can reach the last row.
- [ ] 5. Type a name the phone tends to "correct". The field does not change it.
- [ ] 6. Type a word you said in a memory you kept. The row shows your words around it, with the word in heavier type.
- [ ] 7. Hide a memory, then search for its title. It is not found. Show it again. It is found.
- [ ] 8. On the full archive, the first results show without a visible wait after you open search.
- [ ] 9. With VoiceOver, each result reads as one button with its second line as the value. The rotor's Headings move between "People", "Places", "Things", "What you think" and "Memories".
- [ ] 10. At the largest accessibility text size, every row reads in full and nothing is cut.
- [ ] 11. In Airplane Mode, search works as before.
- [ ] 12. Force-quit the app and open it again. The search field is empty.
- [ ] 13. With the keyboard up, "X" closes search in one tap and shows the tab.
- [ ] 14. Type a query and press Return. "X" closes search in one tap.
- [ ] 15. Tap "X", then tap the field again at once. Search stays open.
- [ ] 16. Start a story from the results with the record bar and finish it. The search screen and its query are still there.
- [ ] 17. With search open, switch to another tab and come back. The query is still there.
- [ ] 18. Search on two tabs. Each tab keeps its own query.
- [ ] 19. With VoiceOver, type a word that is in no memory. VoiceOver says "Nothing found" once, not on each letter.
- [ ] 20. With VoiceOver, the Search button reads "Search".
- [ ] 21. On the full archive, typing does not stutter. This checks the index that folds the words once.
- [ ] 22. Find a person whose relation words came with an unsettled guess. People, the person's page and search show no own words for them until you settle the guess (ruling R7).
- [ ] 23. This build needs no backup of the archive first. This work has no migration. The merged people-and-contacts work has v15, which is already on main.
