# Good first tasks

A living list. Pick one, make a branch, and open a PR (see `CONTRIBUTING.md`). When a task ships, strike it out and link the PR. When you find a new one, add it.

The tasks go from least risk to most. Start at the top.

Sizes: **XS** is under an hour. **S** is an afternoon. **M** is a few sessions and a design pass with Jake.

---

## 1. Pure markdown

No Swift. The safest work, and the work where your ear matters most.

### 1a. Double the opener bank · S

- **File:** `ios/LifelineKit/Sources/LifelineKit/Extraction/Prompts/openers.v1.md`
- **Today:** 40 opening questions. **Target:** about 80.
- **Cover the range:** childhood, family, formative moments (first job, leaving home), casual everyday scenes (a meal, a chore, a street), and open-ended ones ("A day you would live again").
- **Sound inviting, not probing.** Ask for a scene, never a fact (Principle 2). No dates, no "what year", no list of names. A hard chapter is offered lightly with a way out, like the existing "if you want to tell it" (Principle 6). Do not assume a family shape: not everyone had two parents, siblings, or a home they liked.
- **Format rules** (a test checks them):
  - One per line: `id: text`. The id is short and kebab-case (`first-concert`).
  - Every id is unique. A duplicate id is silently dropped.
  - Text ends in `.` or `?`.
  - Add new lines at the bottom. The first four lines are the first session's question and its three alternates. Do not reorder them without Jake.
- **Check:** run `swift test` in `ios/LifelineKit`. `OpeningPromptTests` must pass.
- **Done when:** the file has about 80 openers across all five areas, the tests pass, and the PR lists the new ones grouped by area.

### 1b. Voice and tone pass on the interviewer prompt · S

- **File:** `ios/LifelineKit/Sources/LifelineKit/Interviewer/Prompts/interviewer.v1.md`
- **What it is:** the rules the app's spoken reflections follow during a "Settle in" session.
- **Look for:** any rule or example that could make a reflection feel like evaluation or interpretation (Principle 1). For example: praise ("what a lovely memory"), comfort ("that must have been hard"), summing-up ("so family mattered to you"), or a question that asks for a fact.
- **Do not change** the JSON field names, `none`, `asked_about_app`, `windDown`, or the "Safety check" section. Code reads them. Flag anything there as a comment in the PR instead.
- **Done when:** the PR has a short list of proposed wording changes, each with the principle it serves, and Jake has redlined it. Applying the edits can be a second PR.

---

## 2. UI copy pass

Small Swift edits: you change only the words inside quotes. High taste value.

Before you change any string, search `ios/LifelineUITests/` for it. A few UI tests find a button by its words. If one does, update that test in the same PR.

### 2a. Error and empty-state copy audit · S

- **Where to look:**
  - Error messages: `self.error = "…"` in the `*ViewModel.swift` files under `ios/Lifeline/Screens/`, and `ios/Lifeline/LifelineApp.swift`.
  - Empty states: `ContentUnavailableView(…)` and `Text("No … yet")` in the screen files.
  - Quick search: `grep -rn 'error = \|ContentUnavailableView\|Text("No ' ios/Lifeline`
- **What to look for:** developer-ese. Many errors append the system's raw text, for example `"Could not start audio: \(error.localizedDescription)"` in `Home/HomeViewModel.swift`. The person sees a line like "The operation couldn't be completed (OSStatus -50)". Also "Something is wrong" on the storage-failure screen.
- **Propose:** for each one, a human version that says what happened and what the person can do. Keep the honest part: if a recording was not saved, say so.
- **Done when:** a PR (or a table in an issue first) lists every error and empty state with file, current text, and proposed text, and the agreed changes are applied. Whether to keep the raw system detail (for example behind "Details") is Jake's call; ask.

### 2b. Button labels on the main surfaces · XS–S

- **Session start** (timeline screen): `ios/Lifeline/Screens/Timeline/TimelineScreen.swift` ("Tell a quick story", the Settle in button) and `ios/Lifeline/Screens/AboutYou/FirstOpenScreen.swift`.
- **Memory cards** (Keep / Same story / Change… / Dismiss / Undo): `ios/Lifeline/Screens/Cards/MemoryCard.swift`, plus the other cards in `Screens/Cards/`.
- **Landing** (after a session): `ios/Lifeline/Screens/Landing/LandingScreen.swift` ("Review these moments", "Hide today from the timeline", "Delete today's recording…").
- **Settle-in session:** `ios/Lifeline/Screens/Session/SessionScreen.swift` and `SessionOffers.swift`.
- **Look for:** labels that feel like database actions ("Dismiss") rather than a person's choice. Principle 9: the person must never feel they are maintaining a database.
- **Done when:** a PR changes the labels Jake agrees on, the UI tests pass, and the PR shows a before/after table.

---

## 3. Design plus code

A bounded first real feature. Jake and Danielle pair on this one.

### 3a. Onboarding · M

- **Today:** first launch shows one screen, `ios/Lifeline/Screens/AboutYou/FirstOpenScreen.swift` ("Tell me one story." with Quick story / Settle in / Add a little context). The microphone permission is asked by the system dialog only when the first session starts (`Screens/Home/HomeViewModel.swift`), with no explanation before it. The app never says what it is or where recordings go before it asks.
- **Scope:** a 2–3 screen first-launch sequence that:
  1. says what the app is, in a sentence or two;
  2. explains the microphone (and on-device speech) before the system dialog appears, then asks;
  3. starts the person's first session.
- **Inputs:** the existing designs in `docs/design/` (`R1_FirstOpen`, `Onboard1`–`Onboard3`, `R7_Privacy`; see `docs/design/README.md`), and Principles 1, 2 and 8.
- **Steps:** a short spec in `docs/specs/` → redline with Jake → a plan in `docs/plans/` → build with Claude Code → a UI test that walks the new screens in `-uiTesting` mode (update `LaunchUITests` and `UITestHelpers.skipFirstOpen`).
- **Watch for:** a person who says no to the microphone. They still need a calm way forward.
- **Done when:** a fresh install walks the new screens, reaches a first session, the "mic denied" path is handled, the UI tests pass, and a `docs/DECISIONS.md` entry records the choices.

---

## 4. Later

After the branch → PR → review loop feels routine.

- **Small SwiftUI tweaks** on screens you have already touched: spacing, order, emphasis. Size XS–S each. Done when Jake approves the before/after screenshots.
- **New non-critical features from Phase 2** (`docs/OVERVIEW.md`, "Phase 2: props"): photos as prompts (`docs/design/Photo1`–`Photo3`), music from an era (`Music1`, `Music2`). Size M+. Only after a joint design pass with Jake and a spec in `docs/specs/`.
