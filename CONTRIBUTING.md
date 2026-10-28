# Contributing to Lifeline

This guide is for contributors who are not full-time engineers and work with an AI assistant (Claude Code). Set up first with **First-time setup** in `README.md`. Then pick a task from `docs/GOOD_FIRST_TASKS.md`.

## The one rule above all

**`docs/PRINCIPLES.md` is the source of truth.** If a design choice, a prompt, a line of copy or a feature conflicts with a principle, the principle wins. Read the nine principles (they fit on one screen) and "Design implications" before your first change.

The three that copy and prompt work touch most often:

- **1. The person is the author.** The app never interprets, evaluates or corrects a life. No praise, no judgment, no "that sounds hard".
- **2. Ask for scenes, not facts.** "Tell me about the kitchen", not "What year did you move?"
- **5. Uncertainty is shown, never hidden.** Never fill in a name, date or place the person did not say.

If you are unsure whether something fits, say so in the PR. That is a good question, not a failure.

## Branches and pull requests

### Branch flow

- **Never push to `main`.** All changes reach `main` through a reviewed PR.
- Make one branch per unit of work: one feature, one prompt pass, one copy pass.
- Use short, descriptive branch names: `openers-batch-2`, `copy-error-states`, `onboarding-design`.
- Start each branch from an up-to-date `main`:
  ```bash
  git checkout main
  git pull --ff-only
  git checkout -b openers-batch-2
  ```
- Commit messages are imperative and one line: "Add 12 openers about school and friends". Add a body only when the why is not obvious.
- Push your branch and open a PR on GitHub. A **draft** PR runs no checks; mark it "Ready for review" when you want CI and review.

### What the PR description includes

Copy the shape of PR #10 ("M7 A: facts, feelings and goals leave the timeline") on GitHub. It is a good model. Use these headings:

```markdown
One line: what this is. Link the spec, plan or design if there is one.

## What changes
- 3–6 bullets in plain words: what changes for the person using the app.

## Principles
- Which principle(s) this serves, by number, and how. Required if the PR
  touches the interviewer, prompts, or anything the person reads.

## Tests
- What you ran (`swift test`, UI tests) and the result. Name any new tests.

## Device checklist
1. Steps a reviewer follows in the app to see the change.
```

For a copy-only or markdown-only PR, "What changes", "Principles" and a before/after list of the strings are enough.

### What gets reviewed, and by whom

- **Jake reviews and merges every PR.** Do not merge your own.
- **Tests must be green.** CI runs three checks on every non-draft PR:
  1. **Guards**: block risky things such as a key in the diff, a real phone number or email in a test fixture, or a new network host.
  2. **Kit tests**: `swift test` on a Mac runner.
  3. **Claude review**: posts one summary comment with a verdict (✅ / 🟡 / 🛑) and inline comments. Read it and fix what it flags, or reply to say why not.
- **Design-doc changes** (`docs/PRINCIPLES.md`, `docs/specs/`, `docs/design/`) are redlined together with Jake. Open the PR early as a draft and talk it through. Do not treat them as a solo edit.
- You can ask the GitHub bot a question on any PR or issue by writing `@claude` in a comment.

## Spec-driven development (SDD)

Lifeline is built design-first. Each milestone has a **spec** in `docs/specs/` (what and why) and a **plan** in `docs/plans/` (the ordered tasks, each with its tests). The spec is redlined with Jake before any code. The plan breaks it into small tasks. Then Claude Code works through the plan one task at a time and keeps a ledger at `.superpowers/sdd/<date>-<milestone>/progress.md`. Each ledger line is a task status, a **ruling** (a small judgment call the plan left open, with "cost if wrong"), or a note about a flaky test. Larger, non-obvious rulings graduate into `docs/DECISIONS.md`.

The `.superpowers/` folder is **gitignored**, so the ledgers are on Jake's machine, not in your clone. Ask Jake for the M7 ledger (`2026-10-25-m7-elements/progress.md`) or the M5 ledger (`2026-10-23-m5-organize/progress.md`) as reference, and read them next to `docs/plans/2026-10-25-m7-elements.md`. M6 and M8 shipped without SDD ledgers. That is history, not a model to copy. For your first tasks (openers, copy) you do not need a spec or a ledger. For anything that adds a screen or changes behavior, such as onboarding, write a short spec in `docs/specs/` first and get Jake's redline.

## Tests

### Where tests live

| Kind | Folder | Framework | How to run |
|---|---|---|---|
| Kit tests (logic) | `ios/LifelineKit/Tests/LifelineKitTests/` | Swift Testing (`@Test`, `#expect`) | `cd ios/LifelineKit && swift test` |
| UI tests (the app) | `ios/LifelineUITests/` | XCTest (`XCTestCase`) | Xcode ⌘U on the Lifeline scheme |

Test data is invented. Never use a real person's name, number, email or story in a test or fixture. Fixtures live in `ios/LifelineKit/Tests/Fixtures/`.

### A kit test (Swift Testing)

From `OpeningPromptTests.swift`. One function per behavior, named as a sentence, with `#expect` for each check:

```swift
import Testing
@testable import LifelineKit

@Test func bankLoadsWithHouseFirstAndNoDuplicateIDs() throws {
    let bank = try PromptBank.load()
    #expect(bank.count >= 36)
    #expect(bank.first?.id == "house")
    #expect(Set(bank.map(\.id)).count == bank.count)
}
```

### A UI test (XCTest)

From `LaunchUITests.swift`. The app launches in scripted mode (`-uiTesting`) with a fresh database. Elements are found by `accessibilityIdentifier`, not by their words:

```swift
@MainActor
func testFirstOpenShowsAboutYouAndSkipLeadsHome() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    XCTAssertTrue(app.buttons["firstOpen.quick"].waitForExistence(timeout: 5))
    app.buttons["firstOpen.context"].tap()
    app.buttons["aboutYou.skip"].tap()
    XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
}
```

Shared steps (skip first open, start a session, finish) are in `UITestHelpers.swift`.

### Idioms

- Test names say the behavior: `firstSessionOpensWithTheHouse`, not `testOpener2`.
- Prefer a pure function with a test over a stateful object with a comment.
- Fakes for audio, speech and the network are in `Tests/LifelineKitTests/Fakes/`. Kit tests never call the real API.
- To add a test, ask Claude Code: "Add a Swift Testing test in `<file>` that checks `<behavior>`." Then run `swift test` yourself and read the result.
- **Before you change a visible string, search the UI tests for it.** A few tests find a button by its words (for example `"Add"`). If you change those words, update the test in the same PR.

## Where to add content vs. code

| What | Where | Notes |
|---|---|---|
| Opening questions | `ios/LifelineKit/Sources/LifelineKit/Extraction/Prompts/openers.v1.md` | One per line, `id: text`. Ids must be unique. Text ends in `.` or `?`. |
| Interviewer voice | `ios/LifelineKit/Sources/LifelineKit/Interviewer/Prompts/interviewer.v1.md` | The rules the spoken reflections follow. Changes need a principle cited in the PR. |
| Extractor prompt | `ios/LifelineKit/Sources/LifelineKit/Extraction/Prompts/extractor.v6.md` | How speech becomes memory cards. Jake's area; ask first. |
| Safety responses | `ios/LifelineKit/Sources/LifelineKit/Arc/FixedResponses/` | Fixed words for serious disclosures. Never edit without Jake. |
| UI copy | The SwiftUI view files in `ios/Lifeline/Screens/<Screen>/` | Look for `Text("…")`, `Button("…")`, `Label("…")`. |
| Error messages | The view model next to each screen (`*ViewModel.swift`) | Look for `self.error = "…"`. |
| Permission prompts (mic, speech) | `ios/project.yml` under `info: properties:` | Then run `xcodegen generate`, which rewrites `Info.plist`. Commit both. |
| Screen designs | `docs/design/` (index in `docs/design/README.md`) | Design canvases; redline with Jake. |

## Using Claude Code to help

- `CLAUDE.md` at the repo root is loaded automatically when you start Claude Code in this folder. It gives Claude the project's rules, so you do not need to explain them.
- Start Claude Code in the repo folder and ask in plain words: "Add ten openers about school to the opener bank, in the same style", or "Find every error message on the Settings screen and list them with their file and line."
- Good habits:
  - Ask it to **show you the change before it commits**.
  - Ask it to **run the tests** and tell you the result.
  - Ask "which principle does this touch?" when you are unsure.
  - If an answer goes deep into Swift internals, ask for the plain-words version.
- The repo has no project-specific skills in `.claude/skills/`. Jake uses the **superpowers** Claude Code plugin (brainstorming, writing plans, executing plans). Ask Jake to help you install it when you start a design-plus-code task.

## Decisions log

`docs/DECISIONS.md` is **append-only**, newest first. If your PR makes a non-obvious call (for example "openers never name a family role, because not everyone had a mother at home"), add a dated entry at the top:

```markdown
## 2026-11-02 · Openers never assume a family shape

**Status:** Decided. Source: PR #NN.

**Decision.** …  **Why.** Principle 1 … **Consequences.** …
```

Do not edit or delete an old entry. To change a closed decision, add a new entry that supersedes it.

## Safety

- **No advice.** Never land content (openers, prompts, copy) that gives medical, legal, financial or therapeutic advice. The app listens; it does not counsel. Principle 1.
- **Hard chapters are doors, not destinations** (Principle 6). An opener may offer loss or illness once, lightly, with a way out ("if you want to tell it"). It never pushes.
- **Serious disclosures get fixed words.** Do not write, edit or improvise crisis responses. They live in `Arc/FixedResponses/` and change only with Jake.
- **Never commit secrets.** No API keys, tokens or passwords in any file, commit, screenshot or PR. Your key goes in the app's Settings, where it is stored in the Keychain. `ios/Config/Local.xcconfig` is gitignored; keep it that way.
- **No real people's data.** Sample stories, names and recordings in tests, designs and PRs are invented.
- **Permissions get clear, honest copy.** When the app asks for the mic or speech recognition, the words say what it does and where the data goes ("on this device"). Never request a permission without a reason the person can read first.
- **Data stays on the device.** Do not add analytics, logging of what a person says, or a new network call. A CI guard blocks new hosts.
