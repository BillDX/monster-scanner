# Monster Scanner

A silly, fully offline iPhone party game. Point the camera at a willing friend, "scan" them, and reveal with maximum drama whether they are secretly a vampire, alien, kaiju, werewolf, zombie, robot, ghost, or (disappointingly) a certified human.

**The model narrates, the code decides.** Deterministic Swift code measures the photo and picks the verdict. A small on-device vision-language model (Qwen, from M2) adds observations and funny writing. The game stays fully playable without the model ("Classic Mode").

It is a toy. Scanner readings may be wildly inaccurate.

**Talk slides:** [Monster Scanner: Halloween edition](https://billdx.github.io/monster-scanner/slides/halloween/), from the AI Engineering meetup on local and sovereign AI. Arrow keys move between slides; N shows the speaker notes.

**Status:** 1.0, being prepared for the App Store (M3 done: AI observer, Chaos Mode, sounds, reveal effects, certificate). See [PLAN.md](PLAN.md) for milestones and [PROGRESS.md](PROGRESS.md) for the log.

## Requirements

- Xcode 27.1 or newer (the project uses folder-synchronised groups, Xcode 16+)
- iPhone running iOS 17.0 or newer. Target device: iPhone 14 Pro.
- An Apple Developer team for running on a phone. Team and bundle ID live in [`Config/Shared.xcconfig`](Config/Shared.xcconfig).

## Build and run

### Simulator

Open `MonsterScanner.xcodeproj`, pick the **MonsterScanner** scheme and an iPhone simulator, press Run. The Simulator has no camera; from M1 the game runs from the photo picker there.

### Run on your iPhone

1. Connect the iPhone 14 Pro with a cable, unlock it, and tap **Trust** if asked.
2. Turn on Developer Mode: **Settings → Privacy & Security → Developer Mode**, then restart the phone and confirm. (The option only appears after the phone has been connected to Xcode once.)
3. In Xcode, pick your iPhone as the run destination and press Run. Xcode registers the phone and creates the signing profile automatically.
4. If the phone says "Untrusted Developer", open **Settings → General → VPN & Device Management**, tap your developer certificate, and trust it.

### Testing M1 on your iPhone

Run from Xcode onto the iPhone 14 Pro, then:

1. Turn on **airplane mode**. Everything below should still work.
2. First launch: boot sequence → consent gate → camera permission prompt.
3. Back camera: the reticle follows a face; the bulb button turns on the torch.
4. Front camera: the bulb button fills the screen with violet "UV glow" and full brightness; turning it off restores brightness.
5. Scan a willing friend: heartbeat haptics during the scan, a thump on the reveal, the agent voice reading the dossier.
6. Second Opinion re-rolls (the number always changes; close calls can flip). Scan Again returns to the camera.
7. Point the camera at a wall and scan: "No subject detected" → Declare them a Ghost.
8. Import a photo from the library: the time of day should come from when the photo was taken.
9. Settings → Debug log: any errors or fallbacks show up here, plus the last scan's raw numbers. Please note any head-tilt readings that look wrong.

### Debug launch arguments

Debug builds only (not present in Release):

| Argument | What it does |
|---|---|
| `-MSDebugScan /path/to/image.jpg` | Skips boot and consent and scans that file (the Simulator has no camera) |
| `-MSStubObserver` | A pretend AI observer with a canned playful reading, to check the reveal in the Simulator |
| `-MSShowCertificate` | Opens the certificate a few seconds after the reveal |
| `-MSRunBenchmark [set]`, `-MSRunSoak [set]`, `-MSRunNotesCheck [set]` | On-device model benchmark, 10-scan soak, 50 AI field notes check; use `scripts/run-benchmark.sh` (set `CHECK=-MSRunSoak` etc.) |

### Tests

```bash
cd Packages/MonsterCore && swift test
```

Or the whole scheme on a simulator:

```bash
xcodebuild test -project MonsterScanner.xcodeproj -scheme MonsterScanner -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Project layout

```
MonsterScanner.xcodeproj   Xcode project (folders below are picked up automatically)
Config/Shared.xcconfig     Signing team, bundle ID, version
MonsterScanner/            App target: SwiftUI screens, camera, Vision, haptics, speech
  App/                     App entry point
  DesignSystem/            Colours, fonts, CRT effects
  Features/                One folder per screen (Boot, Consent, Scanner, Scanning, Reveal, Settings)
  Pipeline/                Photo prep, Vision, scene labels, Classic Mode measurements
  Services/                Haptics, narrator voice
  Resources/               Asset catalog, privacy manifest
Packages/MonsterCore/      Pure Swift game logic + unit tests (no UI)
Benchmarks/                M2 model benchmark results (photos are never committed)
docs/slides/halloween/    Talk slides, published with GitHub Pages
docs/privacy/             Privacy policy (GitHub Pages)
Design/AppIcon.svg        Source drawing for the app icon
PLAN.md · PROGRESS.md · DECISIONS.md
```

## Licence

Monster Scanner is free software under the [GNU General Public License v3.0](LICENSE) (GPL-3.0). It's copyleft: you can use, study, share and change it, and anything you distribute that's built from it must stay under the same licence, with its source available.

The dependencies below keep their own licences. The model weights are not in this repository; the app downloads them separately.

## Dependencies and licences

| Dependency | Version | Licence | Used for |
|---|---|---|---|
| [llama.cpp](https://github.com/ggml-org/llama.cpp) prebuilt `llama.xcframework` | `b11799` (`llama-b11799-xcframework.zip`, SHA-256 `9fa07281…9809`) | MIT | On-device inference on Metal, with `mtmd` for image input. Linked into iPhone builds only ([D-016](DECISIONS.md#d-016)) |
| [Qwen3-VL-2B-Instruct GGUF](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF), `Qwen3VL-2B-Instruct-Q4_K_M.gguf` | repo commit `52d6c8f`, 1,107 MB, SHA-256 `089d75c5…c2ae` | Apache 2.0 | Language model for the AI observer |
| Same repo, `mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf` | repo commit `52d6c8f`, 445 MB, SHA-256 `f9a68fab…9c82` | Apache 2.0 | Vision projector (turns the photo into model input) |

- Nothing else is third-party: no Swift packages besides the local `MonsterCore`, and Apple system frameworks for everything else.
- llama.cpp is fetched at build time by `scripts/fetch-llama.sh` into `Vendor/` (not committed).
- The model files aren't in the app bundle. They are downloaded once in the app from the official Qwen org (or by `scripts/fetch-models.sh` for development) and checked against the pinned SHA-256 before loading.
- Full hashes and the pre-flight checks are in [D-015](DECISIONS.md#d-015); the app's pins are in `MonsterScanner/Model/ModelCatalog.swift`.

## Privacy

Full policy: https://billdx.github.io/monster-scanner/privacy/

- Works offline. The only network code (from M2) is the one-time model download from the official Hugging Face org, over HTTPS, verified by SHA-256.
- Photos are analysed on the phone and never leave it. Nothing is written to disk unless you save to Case Files or make a Certificate.
- Shared images have all metadata and location stripped.
- No accounts, analytics, ads or crash reporting. No face recognition and no stored face data.
- Permissions: camera (to scan) and add-only Photos (only if you choose Save Image for a certificate). The app never reads your photo library; imports use the system photo picker.
- Only scan people who said yes.
