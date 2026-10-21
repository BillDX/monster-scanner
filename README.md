# Monster Scanner

A silly, fully offline iPhone party game. Point the camera at a willing friend, "scan" them, and reveal with maximum drama whether they are secretly a vampire, alien, kaiju, werewolf, zombie, robot, ghost, or (disappointingly) a certified human.

**The model narrates, the code decides.** Deterministic Swift code measures the photo and picks the verdict. A small on-device vision-language model (Qwen, from M2) adds observations and funny writing. The game stays fully playable without the model ("Classic Mode").

It is a toy. Scanner readings may be wildly inaccurate.

**Status:** M0 (project setup). See [PLAN.md](PLAN.md) for milestones and [PROGRESS.md](PROGRESS.md) for the log.

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
  Features/                One folder per screen (Boot, …)
  Resources/               Asset catalog, privacy manifest
Packages/MonsterCore/      Pure Swift game logic + unit tests (no UI)
Benchmarks/                M2 model benchmark results (photos are never committed)
PLAN.md · PROGRESS.md · DECISIONS.md
```

## Dependencies and licences

| Dependency | Version | Licence | Used for |
|---|---|---|---|
| *(none yet)* | | | Apple system frameworks only |

Planned for M2, each pinned and added only after approval: llama.cpp prebuilt `llama.xcframework` (MIT) and Qwen model weights (Apache 2.0), downloaded once at runtime.

## Privacy

- Works offline. The only network code (from M2) is the one-time model download from the official Hugging Face org, over HTTPS, verified by SHA-256.
- Photos are analysed on the phone and never leave it. Nothing is written to disk unless you save to Case Files or make a Certificate.
- Shared images have all metadata and location stripped.
- No accounts, analytics, ads or crash reporting. No face recognition and no stored face data.
- Only scan people who said yes.
