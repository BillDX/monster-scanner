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

## D-008 — Type names `SubjectObservations` and `FaceExpression` <a id="d-008"></a>

The spec's protocol returns `Observations`. Apple's current SDKs already ship a type called `Observations` (Observation framework) and one called `Expression` (Foundation), so using those names in the app would be ambiguous.
**Choice:** `SubjectObservations` and `FaceExpression`. JSON keys are unchanged (`hair_color`, `expression`, …), so the model prompt is unaffected.

## D-009 — Verdict scoring numbers <a id="d-009"></a>

- Each clue has a weight of 1–3.5 points; some scale with how strongly they apply (moon fullness, head tilt, frame fill).
- Anomaly factor: 0–2 points per monster, from the seed.
- Human threshold: **3.6** points (was 4; see [D-020](#d-020)). One weak clue (≤ 1.5 points) can never beat it.
- Confidence: 51 + 46 × (1 − e^(−margin/3)) plus a seeded wobble of 0–2.9 points, clamped to 51–99.9. Margin = lead over the runner-up + a quarter of the winning score. Without the wobble, strong photos all landed on 99.6% and Second Opinion looked broken.
- The seed is SHA-256 of the downscaled RGBA pixel bytes plus the calibration number. Pixel bytes rather than JPEG bytes, so encoder differences between iOS versions can't change a verdict.

**Reason:** tests pin the behaviour (every verdict reachable, close calls flip on Second Opinion, neutral photos are human). The numbers will be tuned on the phone in M1 testing; changes get logged here.

## D-010 — Kindness check is a word list in code <a id="d-010"></a>

**Choice:** `ContentPolicy` holds banned terms grouped by topic (appearance, body shape, ethnicity, health, age mockery, violence, insults), matched as whole words. The unit tests run every template (rendered with clues from 400 simulated photos), every clue line, anomaly line and telemetry line through it.
**Reason:** simple, readable, and it fails `swift test` / `xcodebuild test` on a hit. From M3 the same checker screens model-written dossiers before display; a failure falls back to a template.

## D-011 — Where Classic Mode readings come from <a id="d-011"></a>

| Reading | Source |
|---|---|
| Faces, box, roll, yaw | Vision `VNDetectFaceRectanglesRequest` on the 1024 px image |
| Mouth open, eyes open | Vision face landmarks (inner lips, eye outlines) |
| Smiling, eyes closed | Core Image `CIDetector` smile/blink flags (Vision has none) |
| Expression | smiling → sleepy → surprised → serious, in that order. "silly-face" needs the model. |
| Accessories, setting | Vision `VNClassifyImageRequest`, reading only an allow-list of labels (eyeglasses, sunglasses, hats, hoodie, headphones, scarf; places like beach, park, kitchen, living room). Other labels are ignored. |
| Hair colour | Pixel sampling just above the face box; `hidden` if a hat or hood is detected. Readout only (S-2). |
| Shirt colour | Pixel sampling below the chin (most common colour bucket, at least 30% of pixels) |
| Eye colour, age band | Not attempted. Shown as "CLASSIFIED". |
| Blur | Laplacian variance of the face region with margin, so portrait-mode background blur doesn't count |

All of this runs on the phone; nothing is stored.

## D-012 — Narration plays with the silent switch on <a id="d-012"></a>

**Choice:** the audio session uses `.playback` / `.spokenAudio`, ducking other audio. A speaker button on the reveal screen and a Settings toggle turn the voice off.
**Reason:** it's a party game; a narrator that goes quiet because the ring switch is off feels broken. Easy to flip to `.ambient` if you'd prefer it to respect the switch.

## D-013 — Camera setup <a id="d-013"></a>

- `.photo` preset; the photo size is the smallest the camera offers with a long edge of at least 1600 px. Everything is downscaled to 1024 px anyway, and smaller captures are faster.
- Portrait via `videoRotationAngle = 90` (iOS 17 API). The front camera is mirrored in the photo too, so it matches the preview.
- The live reticle runs Vision face rectangles on video frames at most every 0.12 s.

## D-014 — Debug-only scan from a file <a id="d-014"></a>

**Choice:** in Debug builds, the launch argument `-MSDebugScan <path>` skips boot and consent (without saving consent) and scans that image file. Compiled out of Release builds.
**Reason:** the Simulator has no camera, and its sample photos have no people in them. This made it possible to test the whole pipeline headlessly. It will also be the starting point for the M2 benchmark harness.

## D-015 — M2 pre-flight: pinned runtime and model files <a id="d-015"></a>

Checked 2026-10-21 against the GitHub and Hugging Face APIs and the NIST CVE database. **Nothing downloaded yet.**

**Runtime A: llama.cpp prebuilt xcframework (MIT)**

| | |
|---|---|
| Release | `b11799` (published 2026-10-21; llama.cpp ships a build per merged change) |
| Asset | `llama-b11799-xcframework.zip`, 66.8 MB |
| SHA-256 | `9fa07281f680fb38251b45e4e4fcc7cfc74288325461be1dcdc77311efef9809` (GitHub's asset digest; re-check after download) |
| Contents (from `build-xcframework.sh` at that tag) | static libraries, Metal on, **mtmd vision library included** with `mtmd.h` / `mtmd-helper.h`, iOS minimum 16.4, RPC backend not built |
| Architectures at that tag | `qwen3vl` and `qwen35` text models, `QWEN3VL` vision projector |

**Primary model: Qwen3-VL-2B-Instruct, official `Qwen/Qwen3-VL-2B-Instruct-GGUF` (Apache 2.0), repo commit `52d6c8ffea26cc873ac5ad116f8631268d7eb503`**

| File | Size | SHA-256 |
|---|---|---|
| `Qwen3VL-2B-Instruct-Q4_K_M.gguf` | 1,107.4 MB | `089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae` |
| `mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf` (first choice) | 445.1 MB | `f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82` |
| `mmproj-Qwen3VL-2B-Instruct-F16.gguf` (if Q8_0 hurts accuracy) | 819.4 MB | `c3d5afbef5287953acd57b4043d2269456e5761a4eaccb3b71b062996970aea5` |

Download for the first choice: **about 1.55 GB** (resolves [S-3](#s-3)).

**Upgrade candidate: Qwen3.5-2B (Apache 2.0)**

- Qwen publishes `Qwen/Qwen3.5-2B` but **no official GGUF** (as you found).
- Most-used community GGUF: `unsloth/Qwen3.5-2B-GGUF`, repo commit `f6d5376be1edb4d416d56da11e5397a961aca8ae`:
  - `Qwen3.5-2B-Q4_K_M.gguf`, 1,280.8 MB, `aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223`
  - `mmproj-F16.gguf`, 668.2 MB, `7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7`
  - About 1.95 GB. **Needs Bill's approval before use** (publisher: Unsloth).
- MLX route: `ml-explore/mlx-swift-lm` **3.32.3** (2026-09-30) has a Qwen3.5 vision model (`Libraries/MLXVLM/Models/Qwen35.swift`), so Qwen3.5 runs on Runtime B. Weights: `mlx-community/Qwen3.5-2B-4bit`, 1.75 GB.

**Order of work** (unchanged from the spec): Qwen3-VL-2B on llama.cpp first; Qwen3.5-2B only if it beats it on accuracy at acceptable speed; MLX only if llama.cpp misses the budget or Qwen3.5 needs it.

## D-016 — llama.cpp is linked for iPhone builds only <a id="d-016"></a>

The prebuilt `llama-b11799-xcframework.zip` has two slices, `ios-arm64` (iPhone) and `macos-arm64_x86_64`, and **no iOS Simulator slice**. Linking it normally would break every Simulator build and the test runs.
**Choice:**
- The app target finds and links `llama.framework` only for the `iphoneos` SDK (`FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]`, `OTHER_LDFLAGS[sdk=iphoneos*]`).
- A build phase (`scripts/embed-llama.sh`) copies and signs it into the app on device builds only. Script sandboxing is off for the app target so the script can write into the bundle.
- Model code is wrapped in `#if canImport(llama)`. In the Simulator the app reports "AI model: not available in Simulator" and runs Classic Mode.
- `Tools/LlamaProbe` (Mac command-line tool) uses the macOS slice and the same engine source, for quick testing.

**Alternative not taken:** build our own xcframework from source with a Simulator slice. That's more moving parts, and it would no longer be the official prebuilt binary the spec asks for.

## D-017 — Constrained JSON: grammar after top-k, natural whitespace <a id="d-017"></a>

Measured on the Mac with `Tools/LlamaProbe` (M3 Max, Memoji test photos):

| Setup | Generation speed | Output |
|---|---|---|
| No grammar | 130 tok/s | Valid JSON wrapped in a code fence (the parser copes) |
| Grammar over the full vocabulary | 55 tok/s | Valid JSON |
| Grammar, whitespace forced to single spaces | 55 tok/s | Valid JSON, but **invented "glasses, headphones"** on a Memoji wearing neither |
| **Grammar after top-k 40, natural whitespace (chosen)** | **126 tok/s** | Valid JSON, correct readings |

**Choice:** the GBNF grammar (in `ObservationPrompt.grammar`) guarantees the schema; it runs after a top-k of 40, so it checks 40 candidates per step instead of the full ~150k vocabulary. Whitespace stays the model's natural formatting, because squeezing it changed the answers. Greedy decoding, so the same photo gives the same observations. The forgiving parser and single retry stay as a second line of defence.

## D-018 — How the model fits into the scan timing <a id="d-018"></a>

- Classic measurements always run first (well under 1 s). Measurement telemetry starts straight away.
- If the model is ready and the phone isn't hot, the observer reads a crop of the subject (face plus room for hair and shirt, at most 512 px).
- The model call has a 20 s timeout (spec section 6). But the scan only waits until **10.3 s after the shutter**, then quietly uses Classic so the reveal starts within 12 s (spec section 1). In practice the effective timeout is about 10 s.
- Any failure (timeout, invalid JSON twice, load error) falls back silently and is logged on the Debug screen only.
- When the model answers, its observations replace the classic ones; code measurements are untouched. The classic shirt-hue telemetry line is kept only if the model agrees on the shirt colour.

## D-019 — SHA-256 check once per launch, before the first load <a id="d-019"></a>

**Choice:** before the model is loaded for the first time in each app launch, every file is hashed and compared with the pin. A mismatch deletes the files, and the app falls back to Classic until it is downloaded again. Downloads are also hashed as each file lands.
**Reason:** this is the spec's "verify before load, refuse unverified files". The cost on the phone is measured in the M2 benchmark; if it's too slow, the fallback plan is to hash once after download and keep a size + date marker.

## D-020 — Rebalanced after "nearly everyone is a robot" <a id="d-020"></a>

**Problem (Bill, first real scans, 2026-10-21, around lunchtime):** almost every subject came out ROBOT.
**Cause:** Robot's clues described an ordinary photo. A neutral face (2 points), head within 2° of level (2) and a sharp iPhone photo (1.5) add up to 5.5, over the threshold of 4. Most other monsters need something unusual, and in daytime every night-time clue is off. My earlier tests used random clue combinations, not realistic photos, so they missed it.

**Measured:** a realistic party-photo mix in the tests (smiles, common shirt colours, glasses, mostly level heads, by evening and by day) reproduced it: **Robot won 41% of daytime scans**. Real iPhone photos measure about 190–650 on the face-region sharpness score (Simulator sample photos at 512 px), so the old "unnaturally sharp" cut-off of 900 was set from cartoon-like test images.

**Changes**

- Robot's everyday clues are weaker or rarer: serious face 2 → 1.5; level head now < 1° (was < 2°) at 1.5; "unnaturally sharp" needs 1,500 (was 900) and is worth 1; blue or white shirt 2 → 1.5.
- Vampire's black or red shirt 2.5 → 2 (black shirts are very common).
- New daytime clues, all about timing, clothes or framing, so daytime scans vary too:
  - Vampire: indoors in daylight
  - Alien: a loud yellow, purple, pink or orange shirt
  - Kaiju: lunchtime (11:30–14:00)
  - Zombie: afternoon slump (14–17); also "way past bedtime" (01–05)
  - Ghost: drifting at the edge of the frame; slightly soft focus. White shirt 2.5 → 3.
- Human threshold 4 → 3.6.

**Result on the realistic mix (5,000 photos each)**

| | Vampire | Alien | Kaiju | Werewolf | Zombie | Robot | Ghost | Human |
|---|---|---|---|---|---|---|---|---|
| Evening | 23% | 13% | 7% | 21% | 7% | 9% | 6% | 13% |
| Daytime | 20% | 12% | 14% | 12% | 9% | 15% | 5% | 13% |

A new test (`BalanceTests`) fails the build if any monster wins more than 27% or less than 4% of either mix, or if Human leaves 8–25%. The mix is my estimate of real photos; it should be checked against real scans.

## D-021 — Playful, kind detail from the observer <a id="d-021"></a>

**Bill's request (2026-10-21):** find more fun, kind detail in photos (hats, glasses, more nuanced expression reads, a kind funny take on expression); silly and make-believe is fine; never insulting or mean; never mention race or skin colour; very safe guardrails. The accuracy benchmark is on hold.

**What changed**

- Three new free-text fields in the observation JSON (after the spec's seven, which are unchanged and still decide success):
  - `expression_read`: a kind, funny take on the expression, written as a playful comparison, up to 8 words
  - `fun_details`: up to 3 things clearly visible, up to 5 words each (not the shirt colour)
  - `vibe`: one silly, make-believe line about who they secretly are or what they're about to do, up to 12 words
- They are shown and narrated, **never scored**. The verdict still comes only from code ("the model narrates, the code decides").
  - The vibe becomes a "Field note" at the end of the dossier, typed out and read aloud.
  - The expression read appears under Expression.
  - The details form a new "Field notes" readout and "NOTED:" telemetry lines.

**Guardrails, three layers**

1. **Prompt:** warm and playful, compliments and fantasy welcome, no teasing. The free-text fields may only describe clothing, accessories, objects, pose, expression and setting, and must never mention skin or skin colour, race, ethnicity, nationality, religion, body, height, age, looks, health, hair or facial hair. "Only describe what you can clearly see; never invent items." The spec's own kindness sentences are kept word for word.
2. **Grammar:** the free-text fields allow only letters, spaces and light punctuation, with length limits (70 and 100 characters).
3. **Code:** each free-text field goes through `ContentPolicy` in **strict mode**, which adds unkind words ("sad", "awkward", "grumpy", "disappointing"…), age words ("old", "youthful"…) and looks words to the normal list. The normal list now also covers skin (skin, skinned, tanned, complexion), facial hair, more ethnicity and nationality words, religion, and colour-plus-person phrases ("black person", "dark-skinned"), while colours for clothes ("black hat") stay fine. A failing field is dropped on its own; the rest of the reading stays. Over-long text is dropped rather than cut mid-sentence.

Strict mode applies only to AI text. Our own lines may still say the Bureau is "disappointed" by a human verdict, as in the spec.

**Findings on the Mac** (`Tools/LlamaProbe`, Memoji test photos plus one with emoji props: top hat, sunglasses, coffee cup, balloons)

| Prompt version | Result |
|---|---|
| With concrete examples, and "notice hats, glasses…" | **Copied the examples word for word** ("red bobble hat", "wizard on holiday") and invented a hat and glasses |
| No examples, "only what you can clearly see" | Nothing invented, but bland ("happy and ready for a fun day") |
| **Plus form guidance** (comparison for the read, fairy-tale twist for the vibe) — chosen | Props photo: "a top hat", "two red balloons", "a cup of coffee"; read "like a happy, slightly sleepy explorer"; vibe "a whimsical, coffee-sipping adventurer on a magical journey". Plain photos: nothing invented; "like a happy little sunbeam" |

- **Temperature:** 0.6 gave cut-off, vaguer text than greedy, so decoding stays greedy (same photo, same reading).
- **Crash fixed:** with temperature on, my "top-k, then grammar" sampler could pick a token the grammar forbids, and llama.cpp then throws a C++ exception, which would crash the app. Sampling now draws freely, checks that one token against the grammar, and resamples with the grammar over the whole vocabulary only if needed (llama.cpp's own method). That's always valid, and still about 105 tok/s on the Mac.
- **Cost:** the prompt grew from 451 to 706 tokens and the output from about 65 to 95–150 tokens.

**Measured on the iPhone 14 Pro (Debug build, 5 test photos, 2026-10-21)**

| Run | Ordinary photos | Detail-rich photo (150 tokens) | Notes |
|---|---|---|---|
| First build | 8.1–8.6 s | **11.0 s** (past the 10.3 s deadline) | generation 14–16 tok/s |
| After the sampler fix below | **6.4–6.6 s** | **8.5 s** | ~20 tok/s; the 5th photo hit 14 s as the phone heated |
| Phone already hot (thermal "serious") | 15–17 s | 20 s | real scans skip the AI at this heat ([D-018](#d-018)) |

- **Sampler fix:** the check-then-resample sampler first copied all ~152k scores into Swift for every token. In a Debug build that loop cost about 25% of generation speed on the phone. The free sample now runs in llama.cpp's C sampler; only that single token is checked against the grammar, and the Swift full-vocabulary pass runs only on a rare rejection.
- **Compact JSON spacing** (tried again with the new prompt): no token saving, and blander, padded details. Natural spacing stays.
- **Heat matters most.** Back-to-back runs on the charger took the phone to thermal "serious", where generation runs at about half speed. At "serious" the app already uses Classic. At "fair" (state 1), detail-rich photos may miss the deadline and fall back silently. Options were a lite prompt without the playful fields while the phone is warm, or a deadline closer to 11.5 s. **Decision (Bill, 2026-10-21): leave it as is; falling back to Classic when warm is fine.**
- Valid JSON 5/5 on every run, all first try. Peak memory 978 MB.

## D-022 — M3 "AI dossier": the model sees, the code jokes <a id="d-022"></a>

**Spec:** M3 = streamed AI dossier generation (section 4.3) with the template fallback.
**Tried on the Mac with Qwen3-VL-2B** (`Tools/LlamaProbe --dossier / --notes`), with a streaming filter that holds each sentence until complete and drops it unless it passes the strict kindness check and names no other monster:

| Design | Result |
|---|---|
| Full dossier, spec prompt | Lists facts ("Scanner confidence: 85.3%. True age: 192 years."), loops ("It's not." ×6), sometimes never reaches "Recommended action" |
| + repetition penalty, 3–5-sentence grammar, a hand-written template as style example | No loops, right length, some great lines ("a mirror that couldn't decide if it was happy or in mourning for its own reflection"), but it **copied the example's evidence and sentences** |
| Full dossier, no example | Original but rambling; actions cut off mid-sentence |
| Short "field notes" postscript | Repeated the instructions back ("No teasing allowed.", "Joke ideas: …") |
| **"That [thing]? [reason it proves they're a X]." ×2 (grammar-forced)** | Best: "That coffee cup? It proves they're secretly a robot because their caffeine supply is always right in front of them!" About half the lines are still nonsense; some say "this guy" |

**Choice** (a deviation from the spec's M3, chosen for fun and safety):

- The dossier stays a hand-written template (8 per verdict), so it's reliably funny and safe.
- New **exhibit jokes are code-written and slot in what the AI spotted**: "The top hat? Possibly a disguised antenna." There are 8 per verdict, picked by the seed, never about the mask.
- New **subspecies titles** (8 per verdict): "VAMPIRE · Brunch Bat".
- The AI still writes what it's good at: spotted details, the expression read and the make-believe Field note (D-021).
- The streamed AI field notes ship behind **Settings → Mischief → AI field notes (experimental)**, off by default.
  - Every sentence goes through the filter: strict kindness, other-monster names, echoed instructions.
  - On the phone the notes stream in after the reveal, so they never delay it.

**Revisit** with Qwen3.5-2B or a larger model.

## D-023 — Chaos Mode (spec 4.2b) <a id="d-023"></a>

- **How it works:** Settings → Mischief → Chaos Mode (off by default). When the AI observer is ready, the observation call also returns `monster_scores` (0–100 for each monster), with the grammar enforcing the shape. Code clamps the scores; the top score wins, and anything under 40 is overruled to CERTIFIED HUMAN.
- **Kindness:** the evidence lines, dossier and exhibits are still code-written, so the kindness rules hold.
- **Labelling:** case numbers start "C4-"; the reveal shows a CHAOS MODE stamp and "The AI is in charge. The Bureau takes no responsibility."
- **One call, not three:** the spec asks for observations, scores and dossier in one call. The dossier part is left out, because it would push the call past the 12 s budget and the AI dossier is experimental (D-022). Scores and observations do come from one call.
- **Tally:** code and Chaos verdict counts are kept on the phone (Settings → Debug log → Verdict tally) for the spec's comparison. Bill reports them and they're logged in PROGRESS.md. Resolves [S-6](#s-6).

## D-024 — Fun pack pulled forward from M4 <a id="d-024"></a>

Bill asked to make the app "really FUN and funny in every way", so these M4 items landed in M3. Three were built in parallel by helper agents, each in its own git worktree, adding only new files, then reviewed and integrated here:

- **Sound effects** (`Services/SoundFX.swift`, 14 cues), all **synthesised in code** (self-made, so no licences):
  - the scan: power-up, telemetry blips, a drumroll during the reveal blackout
  - a sting per verdict, e.g. organ chord for the vampire, theremin for the alien, a howl for the werewolf, and a sad trombone for Certified Human
  - stamp, burn crackle and glitch
  - a Settings toggle
- **Reveal effects** (`Features/Reveal/RevealEffects.swift`): a short show per verdict with a deadpan caption, e.g. bats and "RECOMMENDED SUNSCREEN: SPF 1,000,000", a UFO borrowing a cow, kaiju stomps with a screen shake, and for Certified Human a confetti fizzle, a stamp slam and a cricket. Reduce Motion gets a still version.
- **Burn the Evidence** (`BurnEffect.swift`): the result chars and burns away, then the app returns to the camera.
- **Certificate of Monsterhood** (`Features/Certificate/`): a parchment certificate with the photo as "Exhibit A", subspecies, true age, clearance, field note, recommended action and a wax seal; a "Certificate of Disappointing Humanity" for humans.
  - The PNG is rendered only when Share is tapped and has no metadata (only IHDR, sRGB, IDAT and IEND chunks).
  - Shared through the system share sheet only.
- **Shake** on the reveal for a Second Opinion (window motion event; no permission).
- **Joke content:** subspecies titles, exhibit jokes, random boot checks and scan flavour lines (D-022).

## D-025 — Audio session: playback, mixed with other apps <a id="d-025"></a>

**Choice:** the sound effects and the narrator share one session: `.playback`, mode `.default`, `.mixWithOthers`. It's never deactivated while the app runs; deactivating it after each narration stopped the effects engine.
**Trade-off:** music from other apps keeps playing at full volume under the narration (no ducking), and sounds play with the silent switch on (D-012). The Settings toggles (Agent voice, Sound effects) are the off switches.

## D-026 — Save the certificate to Photos (add-only permission, approved) <a id="d-026"></a>

The share sheet's "Save Image" (save to Photos) crashes the app unless Info.plist has `NSPhotoLibraryAddUsageDescription`. That's a new permission, and the spec says to ask first.
**Decision (Bill, 2026-10-21):** add it. `NSPhotoLibraryAddUsageDescription` = "Lets you save your Certificate of Monsterhood to Photos when you choose Save Image. Monster Scanner never reads your photo library."
- It's add-only: the app can save, never read or browse the library. iOS asks the first time Save Image is chosen.
- The share sheet still leaves out Assign to Contact (would need Contacts access) and Add to Reading List (meaningless for an image).
- Photo import stays on PhotosPicker, which needs no library permission.

---

## D-027 — More randomness, and the Bureau's after-the-fact reasoning <a id="d-027"></a>

Bill kept getting ROBOT, probably from his navy blue shirt, and asked for "a little more randomness coupled with a silly convoluted rationale (after the fact)".
A test profile like Bill's scans (navy shirt, neutral or smiling, living room, small head tilt, afternoon) came out robot 62%, human 33%, and almost nothing else.
**Decision:** loosen the engine, then let the code invent the logic afterwards.
- **Evidence ceiling.** Clue points now have diminishing returns: `4 × (1 − e^(−points/4))`. One outfit that stacks several robot clues no longer runs away with it.
- **Bigger anomaly.** The random per-monster nudge goes from up to 2.0 to up to 3.0 points.
- **Wild card.** On 35% of scans one random monster gets +3 points. If it wins, the scan shows "⚠ INEXPLICABLE READING DETECTED".
- **Human threshold** 3.6 → 3.8, so CERTIFIED HUMAN stays common (about 1 in 7 overall).
- Still seeded: the same photo and calibration always give the same verdict. Second Opinion and rescans are where the variety shows.
- **Result:** Bill-like scans are now robot 36%, human 25%, alien 12%, zombie 10%, and vampire, kaiju, werewolf and ghost 2–4% each. Night and day spreads keep every verdict between 6% and 19%. A test fails if Bill's profile goes over 45% robot or fewer than six verdicts turn up.
- **The Bureau's reasoning.** A new reveal section under the verdict, shown one numbered step at a time with a blip. It is code-written from pools (`Reasoning.swift`), seeded and checked with the kindness filter:
  1. a fact from the scan (the shirt or an accessory, more often than time, moon, battery or head tilt),
  2. a leap to a silly habit ("people who sleep upside down"),
  3. a bridge from the habit to the verdict, with a made-up statistic,
  4. a wild-card twist ("a lamp flickered. Classic zombie behaviour.") or one real clue,
  5. the conclusion ("Ergo: ZOMBIE. Peer-reviewed by a pigeon."). Humans get a disappointed Bureau.
- Small fix found on the way: clue wording now picks "a" or "an" ("an 80% full moon", "an orange shirt").
- Not done: the reasoning isn't read aloud (the dossier narration is already long) and isn't on the certificate.

---

## D-028 — App Store prep: memory check, privacy policy, icon, 1.0 <a id="d-028"></a>

Bill asked for the App Store prep after the meetup (2026-10-22).
- **Older iPhones get Classic Mode only.** The model peaks just under 1 GB. iOS 17 also runs on 3 and 4 GB iPhones (XR, XS, 11, 12, 13, SE), where that risks the app being killed mid-scan. `DeviceMemory` (MonsterCore, tested) says an iPhone qualifies at 5 GB of physical memory or more, which splits 4 GB and 6 GB phones. On smaller phones the model status is "Needs a 6 GB iPhone", the 1.55 GB download is never offered, and Settings explains why. Even on a 6 GB phone, the model isn't loaded unless iOS allows at least 1.2 GB more; otherwise the scan uses Classic and the next foregrounding tries again. Debug builds can pretend with `-MSFakeMemoryGB 4`.
- **Privacy policy** at https://billdx.github.io/monster-scanner/privacy/ (`docs/privacy/`), written from what the code does: no data collected, photos never leave the phone, one optional download from Hugging Face. App Review requires a link inside the app too, so Settings › About has "Privacy policy". It opens Safari; the app itself still makes no network call besides the model download.
- **App icon:** the Boo Goo ghost inside the app's neon scanner reticle, with a scan beam, on the dark CRT screen. 1024 px, no alpha channel. Source drawing in `Design/AppIcon.svg`.
- **Version 1.0**, build 1.
- **Checked:** Release build has no warnings and contains none of the debug launch switches; App Store archive builds; the embedded `llama.framework` is a signed dynamic library with the right Info.plist (minimum iOS 16.4). Expect an upload warning about missing debug symbols for llama.framework; it doesn't block review.
- **Not done:** the upload itself, App Store Connect metadata, screenshots and the review notes (Bill's steps, with help on request).

---

## Spec issues

Problems found in the spec, with a proposed alternative. Status shows whether Bill has decided.

### S-1 — The front camera has no torch <a id="s-1"></a>

iPhone torches are on the back camera only, so "UV lamp" can't use the flashlight while scanning with the front camera.
**Proposal:** back camera uses the real torch. Front camera shows a "UV glow" instead: the screen around a smaller preview fills with violet light at full brightness (a selfie ring light). If you'd rather keep it simple, the toggle is just hidden on the front camera.
**Status:** accepted by Bill, 2026-10-21.

### S-2 — Hair colour as a verdict clue conflicts with "never use body traits" <a id="s-2"></a>

Section 4.2 says every clue must be about clothing, accessories, setting, timing or pose, but the starter table gives Werewolf "hair colour brown or gray". Natural hair colour is a body trait, and gray hair tracks age, which risks "you look old" jokes.
**Proposal:** hair and eye colour appear only in the neutral observations readout, never as verdict clues. Allowed hair clues are style choices: `hidden` (under a hood or hat) and `dyed-other`. Werewolf loses "brown or gray hair" and gains e.g. "hood or hat" (already listed) and "flannel or plaid shirt".
**Status:** accepted by Bill, 2026-10-21.
**Follow-on:** for the same reason, dossiers (templates now, the AI prompt in M3) don't use the `{hair_color}` and `{eye_color}` slots, and don't use `{age_band}` either; the age joke stays in the readout ("Apparent Earth-age: 30s · True age: 412 years").

### S-3 — Model download size <a id="s-3"></a>

The boot screen text says ≈2.5 GB. A Qwen3-VL-2B Q4 GGUF plus its mmproj file is likely closer to 1.5–2 GB.
**Proposal:** the downloader shows the exact size from the pinned model manifest instead of a hard-coded number.
**Status:** resolved 2026-10-21: the pinned Qwen3-VL-2B files total about 1.55 GB ([D-015](#d-015)).

### S-4 — "Fail the build" on banned content <a id="s-4"></a>

Template checks can gate the build: they run as unit tests in `MonsterCore`, so `swift test` and `xcodebuild test` fail on a hit. The "50 generated dossiers" check needs the model running on the phone, so it can't gate a Mac build.
**Proposal:** an on-device debug harness in M3 generates 50 dossiers, runs the same checker, and its result is logged in PROGRESS.md.
**Status:** done in M3 as `-MSRunNotesCheck` (50 AI field notes; see PROGRESS.md for the result).

### S-5 — "b7824 or newer" is not new enough <a id="s-5"></a>

Checked 2026-10-21. CVE-2026-33298 is as the spec says (GGUF tensor-size integer overflow → heap overflow, CVSS 7.8, fixed in b7824). But a later advisory, **CVE-2026-27940** (high: integer overflow in `gguf_init_from_file_impl`, a bypass of an earlier fix), affects everything up to **b8145** and is fixed in **b8146**. CVE-2026-34159 (critical) is in the RPC backend, which the iOS xcframework doesn't build.
**Proposal:** minimum llama.cpp version is **b8146**; pin `b11799` ([D-015](#d-015)). Before each future pin bump, re-check the llama.cpp security advisories.
**Status:** proposed; applied to the pin.

### S-6 — Chaos Mode has no milestone <a id="s-6"></a>

Section 4.2b doesn't say when Chaos Mode ships. It needs the model, so it's placed in M3.
**Status:** done in M3 ([D-023](#d-023)).

### S-7 — Shake to rescan <a id="s-7"></a>

SwiftUI has no built-in `onShake`. It will be done by catching the shake motion event on the window (UIKit `motionEnded`). This needs no CoreMotion and no permission.
**Status:** note only.

### S-8 — The Simulator has no camera <a id="s-8"></a>

Camera and Metal model performance can only be tested on the phone. In the Simulator the game will run from PhotosPicker (the Simulator has sample photos). All benchmark numbers come from the iPhone 14 Pro.
**Status:** note only.

### S-9 — Two extra kindness tweaks to the clue table <a id="s-9"></a>

- **Kaiju "face fills > 35% of frame (dangerously large)"** could read as "your face is big". Reworded to be about distance: "Subject fills 41% of the frame. Dangerously close to the city."
- **Mask** is never used as a clue, because a mask can be a health item. It still appears in the readout if the model reports it.

**Status:** done in M1; easy to revert if you disagree.

---

## M2 benchmark table

**Status 2026-10-21:** speed, memory and JSON validity are measured on the iPhone 14 Pro with 4 synthetic test photos (Apple's Memoji sample on coloured shirts). Accuracy on real people needs Bill's 10 hand-labelled photos; Qwen3.5-2B is compared on those same photos.

**Memory finding:** peak footprint 958 MB is well under the 2.5 GB budget, so the `com.apple.developer.kernel.increased-memory-limit` entitlement isn't needed.

10 hand-labelled photos. Accuracy is the share of attributes (hair, eyes, shirt, age band, expression, accessories) matching Bill's labels. Raw rows go to `Benchmarks/results.csv`.

| Option | Runtime + release | Model files (SHA-256 pinned) | Download | Load time | Peak memory | s / scan | Valid JSON (of 10) | Attribute accuracy | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Qwen3-VL-2B Q4_K_M + mmproj Q8_0 | llama.cpp b11799 | yes ([D-015](#d-015)) | 1.55 GB | **0.73 s** (+1.41 s SHA-256 check) | **958 MB** | **4.47 s** model, 4.76 s whole pipeline | **4/4** (all first try) | 100% on Memoji test photos; **real photos pending** | iPhone 14 Pro, Debug build, 2026-10-21. ~21 tok/s generation, 1.4 s image + prompt. [CSV](Benchmarks/results-2026-10-21-iphone14pro-memoji.csv) |
| Qwen3.5-2B Q4 | llama.cpp or MLX | | | | | | | | |
| Qwen3-VL-2B 4-bit | mlx-swift-lm (only if needed) | | | | | | | | |
| Qwen3.5-0.8B (only if 2B misses latency) | | | | | | | | | |
| Classic Mode | Vision + pixel sampling | none | 0 | 0 | — | under 0.5 s | n/a | 67% on the same Memoji photos | baseline (no eye colour or age by design) |
