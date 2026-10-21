# Monster Scanner — Plan

Milestones, tasks and status. Keep this in step with [PROGRESS.md](PROGRESS.md): both change in the same commit.

Status key: ✅ done · 🟡 in progress · ⏸ waiting on Bill · ⬜ not started

**Current milestone: M0 — waiting for review.**

---

## M0 — Project setup 🟡

Exit check: the app builds and runs on the iPhone 14 Pro.

- ✅ Xcode project: iOS 17.0, Swift 6, iPhone only, portrait, dark ([D-001](DECISIONS.md#d-001), [D-005](DECISIONS.md#d-005))
- ✅ Local Swift package `MonsterCore` for deterministic game logic, with tests ([D-002](DECISIONS.md#d-002))
- ✅ Boot screen shell (fake BIOS lines, model status, CRT styling)
- ✅ Privacy manifest and camera usage string
- ✅ PLAN.md, PROGRESS.md, DECISIONS.md, README.md
- ✅ Builds and launches on the iOS 17.2 simulator; tests pass on the iOS 27 simulator
- ✅ Compiles for a real iPhone (unsigned build)
- ⏸ Runs on Bill's iPhone 14 Pro (needs the phone connected; see README "Run on your iPhone")
- ⏸ Answer the open questions below before M1 starts

### Open questions for Bill

1. **Hair colour as a verdict clue** — conflicts with "never use body traits" ([S-2](DECISIONS.md#s-2)).
2. **UV lamp on the front camera** — the front camera has no torch ([S-1](DECISIONS.md#s-1)).

---

## M1 — Classic Mode, fully playable without any LLM ⬜

Exit check: the full game loop works in airplane mode.

- ⬜ Consent gate (first launch + Settings), stored in UserDefaults
- ⬜ Camera: AVFoundation preview, front/back switch, shutter, torch "UV lamp"
- ⬜ Vision: face rectangles, landmarks, roll/yaw; live face-tracking reticle
- ⬜ PhotosPicker import (camera denied, and the Simulator path) with EXIF timestamp read
- ⬜ Image prep: largest-face crop, downscale to ≤512 px, strip all metadata
- ⬜ Code measurements: face size %, head tilt, brightness, blur (Laplacian variance), moon phase, local hour, battery, colour sampling (hair/shirt)
- ⬜ Verdict engine: per-monster scoring, seeded anomaly factor (SHA-256 of image bytes + calibration), human threshold, confidence 51–99.9 %, top 3 clues
- ⬜ Clue table expanded; clues limited to clothing, accessories, setting, timing, pose
- ⬜ Dossier templates as JSON: ≥ 8 per monster, same slots as the AI prompt
- ⬜ Scanning sequence: radar sweep, probability gauge, Core Haptics heartbeat, telemetry lines with real values
- ⬜ Reveal: blackout + haptic spike, verdict card, typewriter dossier, AVSpeechSynthesizer voice, observations, clues
- ⬜ Edge cases: no face (Ghost offer), multiple faces (largest), camera denied
- ⬜ Unit tests: determinism, every monster reachable, thresholds incl. human, colour sampler fixtures, moon phase known dates
- ⬜ Content test: every template through the banned-word / banned-topic check

## M2 — Qwen model spike ⬜

Exit check: the DECISIONS.md benchmark table is filled in.

- ⏸ Bill sanity-checks the GGUF in PocketPal on the iPhone first
- ⬜ Verify llama.cpp release (b7824 or newer, CVE-2026-33298 fix); pin tag + SHA-256 ([S-5](DECISIONS.md#s-5))
- ⬜ `ObservationModel` protocol; `ClassicObservationModel` and `LlamaCppObservationModel`
- ⬜ Model downloader: official HF org over HTTPS, Wi-Fi by default, size shown, pinned SHA-256 checked before load
- ⬜ Observation JSON call, retry once, parser tested against 20 malformed outputs
- ⬜ 20 s timeout, thermal-state fallback, memory-warning unload, background unload, boot prewarm
- ⬜ Benchmark harness: 10 hand-labelled photos → CSV (load, peak memory, s/scan, JSON validity, accuracy)
- ⬜ Evaluate Qwen3-VL-2B (llama.cpp), then Qwen3.5-2B; MLX fallback if the primary misses budget
- ⬜ Investigate `increased-memory-limit` entitlement (do not depend on it)

## M3 — AI dossier ⬜

Exit check: 10 consecutive scans, no crash, under 12 s each.

- ⬜ Streamed dossier generation with template fallback
- ⬜ Chaos Mode toggle + banner; log verdict distribution to PROGRESS.md ([S-6](DECISIONS.md#s-6))
- ⬜ On-device harness: 50 generated dossiers through the content check ([S-4](DECISIONS.md#s-4))
- ⬜ 10-scan soak on device

## M4 — Polish ⬜

Exit check: feels like a real app.

- ⬜ Full boot sequence, CRT styling pass, app icon
- ⬜ Sounds (bundled, royalty-free or self-made)
- ⬜ Certificate of Monsterhood (ImageRenderer, share sheet only on tap, no metadata)
- ⬜ Second Opinion, Burn the Evidence, Scan Again, shake to rescan
- ⬜ Case Files (opt-in, encrypted, excluded from backups)

## M5 — Hardening ⬜

Exit check: all tests pass and the checklist is signed off.

- ⬜ Unit test coverage pass
- ⬜ Memory and thermal tests in Instruments
- ⬜ Accessibility: VoiceOver labels, Dynamic Type, reduce motion
- ⬜ Privacy review against spec section 5
- ⬜ Device checklist: airplane mode, cold launch, 10-scan soak, Low Power Mode, both cameras, dark room, bright sun

## Stretch ⬜

- ⬜ Lineup Mode (multiple faces)
- ⬜ Dynamic Island Live Activity "SCAN IN PROGRESS"
- ⬜ Custom monster packs as JSON
- ⬜ Kid mode with extra-gentle templates
