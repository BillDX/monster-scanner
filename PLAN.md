# Monster Scanner — Plan

Milestones, tasks and status. Keep this in step with [PROGRESS.md](PROGRESS.md): both change in the same commit.

Status key: ✅ done · 🟡 in progress · ⏸ waiting on Bill · ⬜ not started

**Current milestone: M2 — playful observer done; accuracy benchmark on hold (Bill's call).**

---

## M0 — Project setup ✅

Exit check: the app builds and runs on the iPhone 14 Pro.

- ✅ Xcode project: iOS 17.0, Swift 6, iPhone only, portrait, dark ([D-001](DECISIONS.md#d-001), [D-005](DECISIONS.md#d-005))
- ✅ Local Swift package `MonsterCore` for deterministic game logic, with tests ([D-002](DECISIONS.md#d-002))
- ✅ Boot screen shell (fake BIOS lines, model status, CRT styling)
- ✅ Privacy manifest and camera usage string
- ✅ PLAN.md, PROGRESS.md, DECISIONS.md, README.md
- ✅ Builds and launches on the iOS 17.2 simulator; tests pass on the iOS 27 simulator
- ✅ Compiles for a real iPhone (unsigned build)
- ✅ Runs on Bill's iPhone 14 Pro (confirmed by Bill, 2026-10-21)
- ✅ Open questions answered (both proposals accepted, 2026-10-21)

### Resolved questions

1. **Hair colour as a verdict clue** — hair and eye colour appear only in the readout ([S-2](DECISIONS.md#s-2), accepted).
2. **UV lamp on the front camera** — screen "UV glow" on the front camera, real torch on the back ([S-1](DECISIONS.md#s-1), accepted).

---

## M1 — Classic Mode, fully playable without any LLM ✅

Exit check: the full game loop works in airplane mode.

- ✅ Device checklist passed on Bill's iPhone 14 Pro, airplane mode (2026-10-21)

- ✅ Consent gate (first launch + Settings), stored in UserDefaults
- ✅ Camera: AVFoundation preview, front/back switch, shutter, torch "UV lamp", front-camera UV glow
- ✅ Vision: face rectangles, landmarks, roll/yaw; live face-tracking reticle
- ✅ PhotosPicker import (camera denied, and the Simulator path) with EXIF timestamp read
- ✅ Image prep: downscale (512 px analysis, 1024 px display), orientation applied, all metadata dropped; largest face used. Face crop for the model moves to M2.
- ✅ Code measurements: face size %, head tilt, brightness, blur (Laplacian variance), moon phase, local hour, battery, colour sampling (hair/shirt)
- ✅ Verdict engine: per-monster scoring, seeded anomaly factor (SHA-256 of image bytes + calibration), human threshold, confidence 51–99.9 %, top 3 clues
- ✅ Clue table expanded (47 clues after the [D-020](DECISIONS.md#d-020) rebalance); clues limited to clothing, accessories, setting, timing, pose ([S-9](DECISIONS.md#s-9))
- ✅ Dossier templates as JSON: 8 per verdict incl. human (64 total)
- ✅ Scanning sequence: radar sweep, probability gauge, Core Haptics heartbeat, telemetry lines with real values
- ✅ Reveal: blackout + haptic spike, verdict card, typewriter dossier paced to the AVSpeechSynthesizer voice, readings, clues
- ✅ Edge cases: no face (Ghost offer, verified), multiple faces (largest), camera denied (explains + photo picker + Settings link)
- ✅ Unit tests: determinism, every monster reachable, thresholds incl. human, colour sampler fixtures, moon phase known dates
- ✅ Content test: every template, clue and telemetry line through the banned-word / banned-topic check

## M2 — Qwen model spike 🟡

Exit check: the DECISIONS.md benchmark table is filled in.

- ✅ Bill sanity-checked the GGUF in PocketPal on the iPhone
- ✅ Verify llama.cpp release and CVEs; pinned b11799 + SHA-256 (minimum raised to b8146, [S-5](DECISIONS.md#s-5))
- ✅ Pin Qwen3-VL-2B GGUF + mmproj files and hashes; check Qwen3.5-2B options ([D-015](DECISIONS.md#d-015))
- ✅ Downloads approved; files fetched and SHA-256 verified (`scripts/fetch-llama.sh`, `scripts/fetch-models.sh`)
- ⏸ Bill approves (or not) the community Qwen3.5-2B GGUF from Unsloth, when we get there
- ✅ `ObservationModel` protocol and `LlamaCppObservationModel` (Classic Mode stays as the code path when no model is available)
- 🟡 Model downloader: official HF org over HTTPS, Wi-Fi by default, size shown, pinned SHA-256 checked before load — built; in-app download not yet tried on the phone
- ✅ Observation JSON call (grammar-constrained, [D-017](DECISIONS.md#d-017)), retry once, parser tested against 20 malformed outputs
- ✅ 20 s timeout plus scan deadline ([D-018](DECISIONS.md#d-018)), thermal-state fallback, memory-warning unload, background unload, boot prewarm
- ✅ Benchmark harness (Debug screen and `-MSRunBenchmark` flag); first run on the iPhone 14 Pro done
- ✅ Fixed "nearly everyone is a robot" from Bill's first real scans; balance test added ([D-020](DECISIONS.md#d-020))
- ⏸ Bill re-tries real scans with the rebalanced build
- ⏸ Accuracy benchmark with 10 labelled photos: on hold (Bill, 2026-10-21)
- ✅ Playful, kind detail fields with three layers of guardrails ([D-021](DECISIONS.md#d-021))
- ✅ Observation time on the iPhone with the longer prompt: 6.5 s ordinary, 8.5 s detail-rich on a cool phone (deadline 10.3 s); much slower when hot ([D-021](DECISIONS.md#d-021))
- ✅ Warm ("fair") phone: keep as is; detail-rich scans may fall back to Classic (Bill, 2026-10-21)
- ⬜ Evaluate Qwen3-VL-2B (llama.cpp), then Qwen3.5-2B; MLX fallback if the primary misses budget
- ✅ Investigate `increased-memory-limit` entitlement: not needed (peak 958 MB)

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
- ✅ Second Opinion and Scan Again (pulled into M1)
- ⬜ Burn the Evidence, shake to rescan
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
