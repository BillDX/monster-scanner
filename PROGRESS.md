# Monster Scanner — Progress log

Newest entry first. Each entry: what changed, what was measured, what's next.

---

## 2026-10-21 — M2 pre-flight

**Changed**

- Pinned the runtime and model files with sizes and SHA-256 ([D-015](DECISIONS.md#d-015)). No downloads yet.

**Measured / found**

- llama.cpp latest is b11799; its xcframework includes the mtmd vision library and Metal, and supports iOS 16.4+.
- The spec's minimum b7824 is too old: CVE-2026-27940 needs b8146 ([S-5](DECISIONS.md#s-5)).
- Real download for Qwen3-VL-2B (Q4_K_M + Q8_0 vision file) is about 1.55 GB, not 2.5 GB ([S-3](DECISIONS.md#s-3)).
- Qwen3.5-2B: no official GGUF; Unsloth's community GGUF is about 1.95 GB. mlx-swift-lm 3.32.3 supports Qwen3.5 with vision; `mlx-community/Qwen3.5-2B-4bit` is 1.75 GB.
- PocketPal (latest v1.20.1) supports vision models, so the same files can be tried there.

**Next**

- Bill: try Qwen3-VL-2B Q4_K_M + mmproj in PocketPal on the iPhone; approve the downloads.

---

## 2026-10-21 — M1 closed, M2 started

**Changed**

- First install on the iPhone 14 Pro from this Mac: paired the phone, enabled Developer Mode, registered the device and created the development profile for `com.williammcintyre.MonsterScanner` (automatic signing, team WUZN2W5PYW).
- M1 signed off: Bill ran the README device checklist on the iPhone in airplane mode and everything passed.

**Next**

- M2 pre-flight: pin the llama.cpp release and the Qwen model files (sizes, SHA-256), check the CVE fix and Qwen3.5 support, then Bill tries the same GGUF in PocketPal before any model code.

---

## 2026-10-21 — M1 part 2: the app (Classic Mode game loop)

**Changed**

- Photo pipeline: downscale, orientation, metadata stripped; EXIF capture time read for imported photos ([D-011](DECISIONS.md#d-011)).
- Vision face detection + landmarks, Core Image smile/blink, allow-listed scene labels for accessories and setting, pixel sampling for hair and shirt.
- Screens: boot (tap to skip), consent gate, scanner (live preview, face reticle, UV lamp/glow, front/back, photo import, pulsing shutter), scanning sequence (radar, gauge, heartbeat haptics, real telemetry), reveal (blackout + haptic spike, verdict card, typewriter dossier paced to the voice, evidence, readings), no-subject Ghost offer, Settings, Debug log.
- Second Opinion and Scan Again, pulled forward from M4.
- Debug-only `-MSDebugScan <path>` launch argument for testing without a camera ([D-014](DECISIONS.md#d-014)).

**Measured (Simulator, iPhone 17 / iOS 27)**

- Test photos made from Apple's bundled Memoji sample image on a coloured "shirt", with EXIF time and fake GPS added.
- Black shirt + EXIF 23:41 → VAMPIRE 80.1 %, case K9-8440. Running it again gave the identical verdict (determinism holds end to end). Shirt read as black, time 23:41 from EXIF, smile detected, face 7 % of frame.
- Blue shirt + 14:00 → ALIEN 75.2 % (head tilt read as 13.9°).
- Landscape sample photo → "NO SUBJECT DETECTED. Are they… invisible?"
- Scan sequence ran about 6 s; reveal and narration worked; the typewriter waits for the voice.
- `xcodebuild test`: 40 tests pass. Release build for a real iPhone compiles. No networking code in the app.
- Fixed: the typewriter would have stalled if the voice never started (now stops waiting after 3 s).

**Not verified yet (needs the iPhone)**

- Camera preview, live reticle, torch, front-camera UV glow, shutter, haptics, the real agent voice, airplane mode.
- Head tilt looked noisy: Vision read the same Memoji head as 0.9° in one photo and 13.9° in another. Probably because it's a cartoon; check on real faces, since 12° triggers the Alien clue.
- Tapping through Second Opinion, Settings and the Ghost button. The input-injection tool didn't work on the iOS 17.2 simulator, and the iOS 27 one needed your approval while you were away.

**Next**

- Bill: device checklist (README → "Testing M1 on your iPhone"). Then tune thresholds from real photos, and M1 is done.

---

## 2026-10-21 — M1 part 1: game logic in MonsterCore

**Changed**

- Evidence types (`SubjectObservations`, `Measurements`, `ScanEvidence`), colour families, moon phase, seeded RNG.
- Clue book: 40 clues across 7 monsters, plus anomaly readings and human reasons. No hair/eye colour, age, or mask clues.
- Verdict engine: seeded, deterministic, human threshold, confidence 51–99.9 %, top 3 clues, no-face Ghost verdict.
- 64 dossier templates (`dossiers.json`), kindness checker, telemetry lines.
- Renamed two types to avoid clashes with Apple SDK types ([D-008](DECISIONS.md#d-008)).

**Measured**

- `swift test`: 39 tests in 5 suites pass on the Mac.
- First run caught two real problems: the banned word "stab" matched "STABLE", and strong verdicts all showed 99.6 % so Second Opinion didn't change the number. Both fixed ([D-009](DECISIONS.md#d-009)).

**Next**

- App side: photo prep, Vision, camera, consent, scanning sequence, reveal.

---

## 2026-10-21 — M0 closed, M1 started

**Changed**

- M0 signed off: Bill ran the app on the iPhone 14 Pro.
- Accepted S-1 (front-camera "UV glow") and S-2 (hair and eye colour only in the readout, never as clues). Recorded in DECISIONS.md.

**Next**

- M1: Classic Mode game loop.

---

## 2026-10-21 — M0 project setup

**Changed**

- Created `MonsterScanner.xcodeproj` (one app target, iOS 17.0, Swift 6, iPhone only, portrait, dark).
- Added the local package `Packages/MonsterCore` with the `Monster` catalogue (7 monsters + human) and its first tests.
- Added a boot screen: fake BIOS lines, "AI MODEL: NOT INSTALLED / MODE: CLASSIC", CRT scan lines and glow. Respects Reduce Motion.
- Added `PrivacyInfo.xcprivacy` (no tracking, no collected data) and the camera usage string.
- Wrote PLAN.md, DECISIONS.md, README.md and this log.

**Measured**

- `swift test` in `Packages/MonsterCore`: 3 tests (10 cases) pass on the Mac.
- `xcodebuild build`, iPhone 15 Pro simulator, iOS 17.2: succeeds, no warnings. App launches and shows the boot screen.
- `xcodebuild test`, iPhone 17 simulator, iOS 27.0: passes.
- Release build for a real iPhone (unsigned, `generic/platform=iOS`): compiles.
- Not measured yet: anything on the iPhone 14 Pro (it wasn't connected).

**Next**

- Bill: run once on the iPhone 14 Pro from Xcode (README → "Run on your iPhone") to close M0.
- Bill: answer the two open questions in PLAN.md (hair-colour clues, front-camera UV lamp).
- Then M1: Classic Mode game loop.
