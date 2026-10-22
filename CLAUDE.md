# Life Timeline — working notes for Claude Code

A voice-first app: a person tells stories from their life, a timeline fills in, and over time it becomes a replayable autobiography. Phase 1 is a personal timeline for one person; family sharing comes later.

## Read these first

- `docs/PRINCIPLES.md` — the grounding document. Eight principles, the literature behind them, the session arc and safety rules. Every prompt, feature and PR is checked against it.
- `docs/OVERVIEW.md` — what we are building, what we are learning, and how it works under the hood (data flow, data model, turn policy).
- `docs/DECISIONS.md` — the decision log. Add an entry when a choice is made; do not re-litigate closed ones without a new entry.
- `docs/TECHNICAL_DESIGN.md` — the detailed design, in progress.
- `docs/design/` — the UX screens (Design canvas sources) with an index.

## Non-negotiables

1. The eight principles in `docs/PRINCIPLES.md` apply to code, prompts and UI copy. In particular: the person is the author; uncertainty is shown, never hidden; every session lands.
2. Data posture (V1): audio, transcripts, timeline and people live on the device. The server is stateless and keeps nothing. Sharing is explicit. Nothing in the server may persist user content.
3. Anything inferred (dates, names, places) is stored and displayed with its uncertainty. Never fill in a detail the person did not say.
4. Serious disclosures get a fixed, pre-written response, never an improvised one.
5. Technical docs under `docs/` use ASD-STE100 style: short sentences, active voice, one instruction per sentence, "must" for requirements.

## Stack (decided 2026-10-21)

- iOS app: Swift / SwiftUI. Recording, on-device speech-to-text with word timestamps, local store (SQLite), turn policy, session arc.
- Server: stateless HTTP service for the interviewer and extractor (text models). Language TBD (TypeScript or Python); see `docs/DECISIONS.md`.
- Web viewer: deferred to Phase 3.
- Voice: cascade (VAD → STT → text model → TTS) behind a `VoiceSession` interface so a realtime speech model can be swapped in later.

## Layout

- `ios/` — `Lifeline/` app target (views, view models, composition root), `LifelineUITests/`, `LifelineKit/` Swift package (all logic; builds on macOS too; `swift test` runs its tests). The Xcode project is generated: run `xcodegen generate` in `ios/` after changing `project.yml`. Simulator runs need an iOS 26 runtime (iPhone 17 Pro, iOS 26.3 on the owner's Mac).
- `server/` — not in V1 (see `docs/DECISIONS.md`)
- `docs/` — everything above
- `docs/experiments/` — research protocols and results; the recording study comes first

## Code quality (owner's standing instruction, 2026-10-21)

- Optimize for clean, modular, readable code the owner can read months later. One responsibility per file. Small types with explicit interfaces. Names that say what a thing is, not how it was built.
- Think about edge cases before writing the happy path: interruptions, empty input, out-of-range values, duplicate events, a kill mid-operation, a missing file or model. Each edge case that matters gets a test or a one-line comment that says why it does not.
- Prefer a pure function with a test over a stateful object with a comment.
- Specs live in `docs/specs/`, plans in `docs/plans/`. Write the design before the code.

## Conventions

- Commit messages: imperative, one line, plus a body when the why is not obvious.
- When adding a feature that touches the interviewer, cite the principle it serves in the PR description.
- Sample content in designs and tests is invented; never use a real person's data as fixtures.
