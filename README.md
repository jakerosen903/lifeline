# Life Timeline

A voice-first app: you tell stories from your life, a timeline fills in, and over time it becomes a replayable autobiography in your own voice. Later, family members' timelines can be shared and fused, memory by memory.

New here? Do **First-time setup** below, then read `CONTRIBUTING.md` and `docs/GOOD_FIRST_TASKS.md`. Before you change anything, read `docs/PRINCIPLES.md`. It is the source of truth.

## First-time setup

Target: from a fresh clone to the app running in the Simulator in about 15 minutes, plus download time.

### What you need

- A Mac on **macOS 26 or later**. The app's code package targets macOS 26.
- **Xcode 27.1** (the version in `ios/project.yml`). Install it from the App Store, open it once, and accept the license.
- An **iOS 26 Simulator runtime**. In Xcode: Settings → Components. The owner uses iPhone 17 Pro on iOS 26.3.
- **Homebrew**, to install XcodeGen: <https://brew.sh>.
- **XcodeGen**: `brew install xcodegen`.
- Access to the GitHub repo, and git set up with your GitHub account.

You do **not** need these to start:

- An Anthropic API key. The scripted mode below runs the whole app without one.
- An Apple Developer account. You need one only to run on a real iPhone.

<!-- TODO(Jake): confirm the minimum macOS. Package.swift says macOS 26; this Mac runs 27.0. Is 26.x enough for Xcode 27.1? -->

### Steps

1. Clone and enter the repo:
   ```bash
   git clone git@github.com:jakerosen903/lifeline.git
   cd lifeline/ios
   ```
2. Make your local config. This file is gitignored. Leave it as it is for the Simulator.
   ```bash
   cp Config/Local.example.xcconfig Config/Local.xcconfig
   ```
3. Generate the Xcode project. The project is gitignored, so a fresh clone does not have it. Run this again whenever `project.yml` changes, or after you pull and Xcode shows missing files.
   ```bash
   xcodegen generate
   ```
4. Open `ios/Lifeline.xcodeproj` in Xcode. Xcode fetches the two Swift packages (GRDB, ZIPFoundation) the first time. Wait for "Resolving packages" to finish.
5. Pick the **Lifeline** scheme and an **iPhone 17 Pro (iOS 26.x)** Simulator in the toolbar.
6. Turn on scripted mode (recommended for your first run): Product → Scheme → Edit Scheme… → Run → Arguments → add `-uiTesting` under "Arguments Passed On Launch".
7. Press **⌘R**. The app opens on "Tell me one story."

### Scripted mode vs live mode

| | Scripted (`-uiTesting`) | Live (no argument) |
|---|---|---|
| Microphone | Not used. A scripted voice "speaks". | Real mic and on-device speech-to-text. |
| Sorting and the interviewer | Scripted answers, no network | Anthropic API, with your key |
| API key | A fake key in memory | You paste one in Settings |
| Data | Fresh, empty database on every launch | Kept between launches |

Use scripted mode for copy, layout and flow work. Use live mode only to hear the real interviewer or test real sorting.

Other launch arguments you can add next to `-uiTesting` (see `ios/Lifeline/Dependencies.swift`):

- `-uiTesting-noKey`: act as if no key is saved.
- `-uiTesting-slow`: a new segment every few seconds, not every second.
- `-uiTesting-speaks`: the app speaks its lines out loud.

### Live mode and the API key

- Sorting, duplicate checks and the interviewer call the Anthropic API. Without a key the app still records and transcribes. Moments wait as "sorting" until a key is added.
- Get a key from <https://console.anthropic.com>. It starts with `sk-ant-`.
- In the app: Settings → paste the key → Save. It goes into the device Keychain. It is never in the repo.
- Never put a key in a file, a commit, a screenshot or a PR. A CI guard blocks keys in the diff.

<!-- TODO(Jake): decide which key Sarah uses for live mode (her own Console account, or a shared dev key with a spend limit) and write it here. -->
<!-- TODO(Jake): confirm live mode works in the Simulator: mic input through the Mac, and on-device speech (SpeechAnalyzer) model download. If it does not, say "live mode needs a real iPhone". -->

### Run the tests

- **Kit tests** (all the logic; fast; no Simulator). This is what CI runs on every PR:
  ```bash
  cd ios/LifelineKit
  swift test
  ```
- **UI tests** (drive the app in the Simulator; slower): in Xcode, pick the Lifeline scheme and press **⌘U**. Or:
  ```bash
  cd ios
  xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  ```
- You can also run one kit test from Xcode: open `ios/LifelineKit/Package.swift` in Xcode and click the diamond next to the test.

### Run on a real iPhone (optional)

1. Add your Apple ID in Xcode → Settings → Accounts.
2. In `ios/Config/Local.xcconfig`, set `DEVELOPMENT_TEAM` to your team ID and `BUNDLE_ID_PREFIX` to something unique to you (for example `com.yourname`).
3. Run `xcodegen generate` again, plug in the phone, pick it in the toolbar, and press ⌘R.
4. The first time, trust the developer on the phone: Settings → General → VPN & Device Management.

<!-- TODO(Jake): confirm a free personal team can sign this app (the UIBackgroundModes audio entitlement and the exported .lifeline type). -->

## Status

V1 milestones M1–M8 have shipped: record, transcribe, extract and confirm, place, land, organize, steady, memory kinds and entities, and the spoken interviewer. Plans are in `docs/plans/`, specs in `docs/specs/`, and the decision log in `docs/DECISIONS.md`.

## Stack

iOS native (Swift/SwiftUI). All logic lives in the `ios/LifelineKit` Swift package; the `ios/Lifeline` app target holds the screens. There is no server in V1: the app calls the Anthropic API directly with a key stored in the Keychain. The web viewer is deferred to Phase 3. See `docs/DECISIONS.md`.

## Layout

- `ios/Lifeline/` — the app: screens (`Screens/`), wiring (`Dependencies.swift`).
- `ios/LifelineKit/` — the logic package and its tests (`Tests/LifelineKitTests/`).
- `ios/LifelineUITests/` — UI tests that drive the app in scripted mode.
- `ios/project.yml` — the XcodeGen source for the Xcode project.
- `docs/` — principles, overview, decisions, specs, plans, designs.

## Troubleshooting

- **"Config/Local.xcconfig" not found, or `xcodegen` fails.** Do step 2 of setup, then run `xcodegen generate`.
- **Xcode shows files in red, or a new screen is missing.** Someone changed `project.yml` or added files. Run `xcodegen generate` in `ios/` and reopen the project.
- **"No such module 'LifelineKit'" or package errors.** File → Packages → Reset Package Caches, then build again.
- **Strange kit-test crashes after switching branches.** Run `swift package clean` in `ios/LifelineKit`, then `swift test` again.
- **Known flaky tests.** These sometimes fail on a full run and pass when run alone. They are not caused by your change:
  - `SegmentPlayerTests.playStartsAtRangeStartAndStopsAtRangeEnd` (depends on the Mac's audio output)
  - `SessionRecorderTests.stopReturnsBeforeExtractionFinishes` (timing under load)
  - Some `BackupTests` (these write real files into `~/Documents`)
  - UI tests that time out while another build runs. Rerun the one test on a quiet Simulator.
