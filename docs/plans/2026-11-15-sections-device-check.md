# Device check: the five-sections shell

The owner ticks each item on the iPhone. Each item is one check. Build and install the `sections-shell` branch first. Plan: `docs/plans/2026-11-15-sections.md`.

- [ ] 1. The tab bar and the record bar show in light and dark appearance, and with Reduce Transparency on.
- [ ] 2. At the largest accessibility text size, the bar's label truncates and the bar stays tappable. A start error on the bar stays readable.
- [ ] 3. VoiceOver reads the bar's main button with the page's label, and its menu as "More ways to start". It reads each tab by its title.
- [ ] 4. A quick story started from a person's page opens with that person's question, records, and lands. The Sessions list shows it.
- [ ] 5. Barge-in and the quiet command still work in a settle-in session started from the bar's menu. (These are the M8 checks. Skip them if the M8 device run is done.)
- [ ] 6. Kill the app mid-session. On relaunch, the landing shows over the tabs.
- [ ] 7. Back up the archive, then install. The v12 migration runs, and every earlier session opens.
- [ ] 8. Restore a backup made before this build. Every earlier session opens.
- [ ] 9. With the microphone refused, tap the bar, then tap Open Settings. The Lifeline page in Settings opens.
