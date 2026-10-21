# Monster Scanner — Progress log

Newest entry first. Each entry: what changed, what was measured, what's next.

---

## 2026-10-21 — M3: the AI dossier, and a lot more fun

**Changed**

- Tried four AI-dossier designs on the Mac. Shipped the funniest reliable one: hand-written dossier, code-written exhibit jokes from what the AI spotted, subspecies titles, and AI field notes as an experimental switch ([D-022](DECISIONS.md#d-022)).
- Chaos Mode ([D-023](DECISIONS.md#d-023)), with a CHAOS MODE stamp and a code-vs-chaos tally.
- Fun pack pulled forward from M4 ([D-024](DECISIONS.md#d-024)), three parts built by helper agents in separate worktrees:
  - sound effects synthesised in code
  - per-monster reveal effects
  - Burn the Evidence
  - the Certificate of Monsterhood
  - shake for a Second Opinion
  - random boot checks and joke lines in the scan
- Strict kindness mode now also covers hair and body words (found by the 50-note check).
- Engine: optional repetition penalty; the free sample stays in C (grammar check per token).
- Telemetry speeds up once results are in, so extra jokes don't make the scan drag. The scan ends by 10 s, then a 1.1 s drumroll blackout. The shutter-to-reveal time is logged on the Debug screen.
- Audio: one shared session for narrator and effects ([D-025](DECISIONS.md#d-025)). Certificate sharing leaves out Save to Photos pending a permission decision ([D-026](DECISIONS.md#d-026)).

**Measured (iPhone 14 Pro, Debug build)**

- 10-scan soak (test photos, back to back on the charger): no crash; shutter to reveal 7.3–9.1 s; peak 953 MB. The phone reached thermal "fair" at scan 6 and "serious" at scan 8; scans 9–10 fell back to Classic as designed.
- 50 AI field notes through the strict checker (S-4): 187 sentences kept, 13 dropped, **0 unkind sentences kept**, 0 notes empty. Quality is uneven; the feature stays off by default.
- Simulator (stub observer): the full sequence renders: scan with observer lines, drumroll blackout, red flash and bats, settle; the certificate renders well.
- 69 core tests pass; simulator and iPhone builds have no warnings.

**Not verified**

- Sounds have not been heard by a person, only measured.
- The share sheet hasn't been tapped through.
- Chaos Mode on real photos.

**Next**

- Bill: real scans with sound on; try Chaos Mode; decide on the Save-to-Photos permission.

---

## 2026-10-21 — Playful observer: speed on the iPhone

**Changed**

- Sampler: the free sample stays in llama.cpp's C code; the Swift full-vocabulary pass only runs when the grammar rejects a token. Restores ~20 tok/s on the phone (was 14–16).
- Benchmark CSV and summary now record the phone's thermal state for each photo.

**Measured (iPhone 14 Pro, Debug, 5 test photos)**

- Cool phone: 6.4–6.6 s per ordinary photo, 8.5 s for the detail-rich one (150 tokens). Deadline 10.3 s. Valid JSON 5/5. Peak 978 MB.
- Before the fix the detail-rich photo took 11.0 s (would have fallen back to Classic).
- After several back-to-back runs on the charger the phone sat at thermal "serious" and took 15–20 s per photo; real scans use Classic at that heat.
- Compact JSON spacing gave no saving with the new prompt (Mac).

**Next**

- Bill: real scans to judge the tone of the new details.
- Decided by Bill: when the phone is warm, falling back to Classic is fine; no lite prompt for now.

---

## 2026-10-21 — Playful, kind detail from the AI observer

**Changed** ([D-021](DECISIONS.md#d-021))

- New observation fields: `expression_read`, `fun_details`, `vibe`. Shown in the reveal (Field note in the dossier, read aloud; expression read; Field notes row) and in telemetry. Never scored.
- Guardrails: prompt rules; grammar limits; strict kindness check on all AI text (unkind, age and looks words, skin, ethnicity, religion, colour-plus-person phrases). A failing field is dropped on its own.
- Sampler fixed: check-then-resample grammar sampling, so a forbidden token can never reach llama.cpp (that would have crashed the app when sampling with temperature).
- Parser: sunglasses win over glasses; settings don't end on filler words; over-long playful text is dropped, not chopped.
- Template test now renders every template for every verdict (it was missing Human's templates).
- Debug-only `-MSStubObserver` (canned playful reading) to check the reveal in the Simulator.

**Measured**

- Mac: correct, kind details on a props photo, nothing invented on plain photos; 1.1–1.6 s per photo (was 0.7 s). Prompt-wording experiments are in D-021.
- Simulator, with the stub observer: the Field note renders and is narrated; the stub's sunglasses produced "Sunglasses indoors" through the normal clues.
- 55 core tests pass; the scheme tests pass.
- Not measured: time on the iPhone (the phone wasn't reachable at the end of this session).

**Next**

- Speed check on the iPhone, then real scans to judge the tone.

---

## 2026-10-21 — Accuracy benchmark ready to run

**Changed**

- `scripts/run-benchmark.sh`: copies `Benchmarks/photos/` + `labels.csv` to the phone as a named set, runs the benchmark, and copies results to `Benchmarks/private/` (git-ignored, since the readings describe real people).
- The benchmark reads per-set folders on the phone (`-MSRunBenchmark <set>`), so the old Memoji photos never mix into real results.
- `Benchmarks/README.md` explains the labels and the scoring; an empty `labels.csv` template is in `Benchmarks/photos/`.

**Measured**

- Dry run with the Memoji set: the script found the phone and copied the photos; the launch was refused because the phone was locked (now reported plainly). The copy-back step reuses commands that worked earlier but hasn't run end to end through the script yet.

**Next**

- Bill adds 10 labelled photos, then runs `scripts/run-benchmark.sh` (or asks me to).

---

## 2026-10-21 — Fix: nearly every subject was a robot

**Found by Bill** on the first real scans with the AI observer.

**Changed**

- Rebalanced the clue table and lowered the human threshold to 3.6; added 7 daytime-friendly clues (now 47). Details and before/after numbers in [D-020](DECISIONS.md#d-020).
- Added a realistic party-photo mix to the tests (evening and daytime) and a balance test that fails if any verdict wins over 27% or under 4%.
- The neutral test fixture moved from 14:00 to 10:00 so the new afternoon clue doesn't fire on it.

**Measured**

- Before: Robot won 41% of simulated daytime scans. After: every verdict 5–23% by evening and by day, Human 13%.
- Real iPhone photos score about 190–650 on the sharpness measure, so "unnaturally sharp" now needs 1,500.
- 49 tests pass. Installed on Bill's iPhone.

**Next**

- Bill: a few more real scans to confirm the variety feels right (Settings → Debug log shows each scan's scores).

---

## 2026-10-21 — M2: first benchmark on the iPhone 14 Pro

**Measured (Debug build, 4 Memoji test photos)**

- SHA-256 check of both files at launch 1.41 s; model load 0.73 s; peak footprint 958 MB.
- AI observation 4.39–4.54 s per photo (about 1.4 s image encode + prompt, ~65 tokens at ~21 tok/s); whole pipeline 4.8 s. The scan animation runs 5.5 s, so shutter to reveal stays around 6 s (budget 12 s).
- Valid JSON 4/4, all on the first try. Readings 100% right on the Memoji photos vs 67% for Classic Mode; not meaningful until real photos are used.
- The first run's numbers were thrown away: a timing bug (set in a `defer`, after the result was copied) gave 0 s per scan, and the benchmark loaded a second model copy while the boot screen was still hashing the first, giving a bogus 15.7 s load. Both fixed; the benchmark now reuses the launch-time load.

**Next**

- Bill: 10 hand-labelled photos → accuracy for Qwen3-VL-2B and Classic.
- Then Qwen3.5-2B on the same photos (needs approval for Unsloth's community GGUF, or the MLX route).
- Try the in-app model download on the phone.

---

## 2026-10-21 — M2: Qwen3-VL-2B running through llama.cpp

**Changed**

- Fetched and verified llama.cpp b11799 and the Qwen3-VL-2B files (scripts in `scripts/`).
- MonsterCore: observation prompt, GBNF grammar, forgiving parser (20 malformed-output tests).
- `LlamaEngine` (Swift over the llama.cpp + mtmd C API), `LlamaCppObservationModel`, model store, downloader, `ModelService` (verify, load, unload on memory warning or background, thermal fallback).
- Scans use the AI observer when ready, with silent Classic fallback ([D-018](DECISIONS.md#d-018)). Settings has an AI section (download, Wi-Fi only by default, delete, on/off); the boot screen shows the model status.
- llama.cpp is linked for iPhone builds only; there's no Simulator slice ([D-016](DECISIONS.md#d-016)).
- Debug-only benchmark harness writing CSV to the app's Documents folder.

**Measured (Mac, M3 Max, Memoji test photos)**

- Load 0.4 s; observation 0.7 s per photo (451 prompt tokens, 65 generated at 126 tok/s); valid JSON every time; readings correct for a cartoon.
- Grammar over the full vocabulary was 2.3× slower, and forcing compact whitespace made the model invent accessories ([D-017](DECISIONS.md#d-017)).
- Tests: 47 pass. Simulator build (no llama) and iPhone build (llama embedded and signed) both succeed.

**Next**

- Run the benchmark on the iPhone 14 Pro; then Bill's 10 hand-labelled photos for the accuracy column.

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
