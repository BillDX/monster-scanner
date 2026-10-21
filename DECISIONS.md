# Monster Scanner — Decisions

Every significant technical choice: options considered, measurements, choice, reason.
Spec problems are listed separately under [Spec issues](#spec-issues).

---

## D-000 — Development environment

Recorded 2026-10-21 (fills in the spec's placeholders in section 1).

| Item | Value |
|---|---|
| Mac | MacBook Pro, Apple M3 Max, 96 GB (Mac15,10) |
| macOS | 26.6.2 (25G83) |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4 |
| Signing | Paid Apple Developer account, individual team `WUZN2W5PYW`. No 7-day expiry. |
| Test device | iPhone 14 Pro (A16, 6 GB) |
| Simulators used | iPhone 15 Pro / iOS 17.2 (deployment floor), iPhone 17 / iOS 27.0 (current) |

## D-001 — How the Xcode project is defined <a id="d-001"></a>

**Options**

1. Hand-written `.xcodeproj` using folder-synchronised groups (Xcode 16+).
2. XcodeGen (`project.yml` → `.xcodeproj`). Installed on this Mac, but every contributor needs it and the project must be regenerated whenever files change.
3. Tuist. Adds a tool dependency.
4. SwiftPM only. Can't produce a signed iOS app with an Info.plist, entitlements and an asset catalog on its own.

**Choice:** option 1.
**Reason:** any file added under `MonsterScanner/` is compiled automatically, so `project.pbxproj` rarely changes and diffs stay small. No extra tools. Opens directly in Xcode.

## D-002 — Game logic lives in a local package, `MonsterCore` <a id="d-002"></a>

**Options:** everything in the app target · a local Swift package for the pure logic.

**Choice:** local package at `Packages/MonsterCore` (no UIKit or SwiftUI).
**Reason:** "the code decides" logic (monsters, clues, verdict engine, moon phase, JSON parsing, templates, content checks) is pure and deterministic. In a package it is tested with `swift test` on the Mac in about a second, without a simulator. The app scheme runs the same tests through `xcodebuild test`. It is our own code, not a third-party dependency.

Camera, Vision, haptics, speech and model runtimes stay in the app target.

## D-003 — Swift 6 concurrency settings <a id="d-003"></a>

**Choice:**

- App target: Swift 6 language mode, default actor isolation `MainActor`, approachable concurrency on (the Xcode 26+ template defaults).
- `MonsterCore`: Swift 6 language mode, standard (nonisolated) default; all public types are `Sendable` value types.

**Reason:** UI code stays simple and checked. Work that must leave the main thread (camera session, Vision requests, model inference) will be explicit `actor`s or `nonisolated` types, so it's obvious in review where concurrency happens.

## D-004 — Signing and bundle ID <a id="d-004"></a>

**Choice:** automatic signing, team `WUZN2W5PYW`, bundle ID `com.williammcintyre.MonsterScanner`. Both are set in [`Config/Shared.xcconfig`](Config/Shared.xcconfig), not in the project file.
**Reason:** one place to change them. A paid account also makes the `com.apple.developer.kernel.increased-memory-limit` entitlement an option for M2 (still to be checked; we won't depend on it).

## D-005 — iPhone only, portrait only, dark only <a id="d-005"></a>

**Choice:** `TARGETED_DEVICE_FAMILY = 1`, portrait, `UIUserInterfaceStyle = Dark`.
**Reason:** the camera UI and CRT look are designed for a phone held upright in the dark theme. Fewer layouts to build and test. Easy to revisit.

## D-006 — Test framework <a id="d-006"></a>

**Choice:** Swift Testing (`import Testing`) for unit tests. XCTest only where Swift Testing can't do the job (performance metrics, UI tests).
**Reason:** parameterised tests (`arguments:`) suit "every monster is reachable" and "20 malformed JSON outputs". Ships with Xcode, so no dependency.

## D-007 — Info.plist and privacy manifest <a id="d-007"></a>

**Choice:** Info.plist generated from build settings (`GENERATE_INFOPLIST_FILE`). `NSCameraUsageDescription` is the only permission string. `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and UserDefaults access (reason `CA92.1`, for the consent flag and settings).
**Reason:** fewer files; every permission is visible in one place in the build settings.

---

## Spec issues

Problems found in the spec, with a proposed alternative. Status shows whether Bill has decided.

### S-1 — The front camera has no torch <a id="s-1"></a>

iPhone torches are on the back camera only, so "UV lamp" can't use the flashlight while scanning with the front camera.
**Proposal:** back camera uses the real torch. Front camera shows a "UV glow" instead: the screen around a smaller preview fills with violet light at full brightness (a selfie ring light). If you'd rather keep it simple, the toggle is just hidden on the front camera.
**Status:** waiting for Bill.

### S-2 — Hair colour as a verdict clue conflicts with "never use body traits" <a id="s-2"></a>

Section 4.2 says every clue must be about clothing, accessories, setting, timing or pose, but the starter table gives Werewolf "hair colour brown or gray". Natural hair colour is a body trait, and gray hair tracks age, which risks "you look old" jokes.
**Proposal:** hair and eye colour appear only in the neutral observations readout, never as verdict clues. Allowed hair clues are style choices: `hidden` (under a hood or hat) and `dyed-other`. Werewolf loses "brown or gray hair" and gains e.g. "hood or hat" (already listed) and "flannel or plaid shirt".
**Status:** waiting for Bill.

### S-3 — Model download size <a id="s-3"></a>

The boot screen text says ≈2.5 GB. A Qwen3-VL-2B Q4 GGUF plus its mmproj file is likely closer to 1.5–2 GB.
**Proposal:** the downloader shows the exact size from the pinned model manifest instead of a hard-coded number. Measure in M2.
**Status:** to verify in M2.

### S-4 — "Fail the build" on banned content <a id="s-4"></a>

Template checks can gate the build: they run as unit tests in `MonsterCore`, so `swift test` and `xcodebuild test` fail on a hit. The "50 generated dossiers" check needs the model running on the phone, so it can't gate a Mac build.
**Proposal:** an on-device debug harness in M3 generates 50 dossiers, runs the same checker, and its result is logged in PROGRESS.md.
**Status:** proposed.

### S-5 — llama.cpp release and CVE not yet verified <a id="s-5"></a>

Release `b7824` and CVE-2026-33298 haven't been checked yet.
**Plan:** at the start of M2, confirm against the llama.cpp GitHub release notes and the advisory before downloading anything, then record the exact tag and the xcframework's SHA-256 here.
**Status:** to verify in M2.

### S-6 — Chaos Mode has no milestone <a id="s-6"></a>

Section 4.2b doesn't say when Chaos Mode ships. It needs the model, so it's placed in M3.
**Status:** proposed.

### S-7 — Shake to rescan <a id="s-7"></a>

SwiftUI has no built-in `onShake`. It will be done by catching the shake motion event on the window (UIKit `motionEnded`). This needs no CoreMotion and no permission.
**Status:** note only.

### S-8 — The Simulator has no camera <a id="s-8"></a>

Camera and Metal model performance can only be tested on the phone. In the Simulator the game will run from PhotosPicker (the Simulator has sample photos). All benchmark numbers come from the iPhone 14 Pro.
**Status:** note only.

---

## M2 benchmark table (to fill in)

10 hand-labelled photos. Accuracy is the share of attributes (hair, eyes, shirt, age band, expression, accessories) matching Bill's labels. Raw rows go to `Benchmarks/results.csv`.

| Option | Runtime + release | Model files (SHA-256 pinned) | Download | Load time | Peak memory | s / scan | Valid JSON (of 10) | Attribute accuracy | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Qwen3-VL-2B Q4 | llama.cpp b____ | | | | | | | | |
| Qwen3.5-2B Q4 | llama.cpp or MLX | | | | | | | | |
| Qwen3-VL-2B 4-bit | mlx-swift-lm (only if needed) | | | | | | | | |
| Qwen3.5-0.8B (only if 2B misses latency) | | | | | | | | | |
| Classic Mode | Vision + pixel sampling | none | 0 | 0 | | | n/a | | baseline |
