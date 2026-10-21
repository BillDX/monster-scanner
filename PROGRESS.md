# Monster Scanner — Progress log

Newest entry first. Each entry: what changed, what was measured, what's next.

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
