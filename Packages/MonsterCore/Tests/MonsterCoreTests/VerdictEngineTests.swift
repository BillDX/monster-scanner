import Testing
@testable import MonsterCore

@Suite("Verdict engine")
struct VerdictEngineTests {
    // MARK: Determinism

    @Test("Same evidence and seed give the same verdict")
    func deterministic() {
        for evidence in Fixtures.random(count: 200) {
            let a = VerdictEngine.decide(evidence, seed: Fixtures.seed(0))
            let b = VerdictEngine.decide(evidence, seed: Fixtures.seed(0))
            #expect(a == b)
        }
    }

    @Test("Seed depends on image bytes and calibration")
    func seedInputs() {
        #expect(Fixtures.seed(0) == Fixtures.seed(0))
        #expect(Fixtures.seed(0) != Fixtures.seed(1))
        #expect(Fixtures.seed(0, bytes: [1, 2, 3, 4]) != Fixtures.seed(0, bytes: [1, 2, 3, 5]))
    }

    @Test("A different calibration gives a different result")
    func calibrationChangesOutput() {
        for (monster, evidence) in Fixtures.strong {
            let a = VerdictEngine.decide(evidence, seed: Fixtures.seed(0))
            let b = VerdictEngine.decide(evidence, seed: Fixtures.seed(1))
            #expect(a.scores.map(\.anomaly) != b.scores.map(\.anomaly))
            #expect(a.confidence != b.confidence, "\(monster): \(a.confidence) both times")
            #expect(a.caseNumber != b.caseNumber || a.trueAgeYears != b.trueAgeYears)
        }
    }

    @Test("Second Opinion can flip a close call")
    func secondOpinionFlipsCloseCalls() {
        // Vampire 4.0 (black shirt + shadows) vs zombie 4.5 (sleepy + dim).
        let close = Fixtures.evidence { m, o in
            o.shirtColor = "black"; o.expression = .sleepy
            m.brightness = 0.2
        }
        let verdicts = Set((0..<50).map { VerdictEngine.decide(close, seed: Fixtures.seed($0)).monster })
        #expect(verdicts.contains(.vampire))
        #expect(verdicts.contains(.zombie))
        #expect(!verdicts.contains(.human))
    }

    // MARK: Reachability and thresholds

    @Test("Every verdict is reachable, whatever the calibration", arguments: Monster.allCases)
    func everyMonsterReachable(_ monster: Monster) throws {
        let evidence = try #require(Fixtures.strong[monster])
        for calibration in 0..<50 {
            #expect(VerdictEngine.decide(evidence, seed: Fixtures.seed(calibration)).monster == monster)
        }
    }

    @Test("Nothing suspicious means CERTIFIED HUMAN")
    func neutralIsHuman() {
        for calibration in 0..<100 {
            #expect(VerdictEngine.decide(Fixtures.neutral, seed: Fixtures.seed(calibration)).monster == .human)
        }
    }

    @Test("One weak clue can't beat the human threshold")
    func weakClueStaysHuman() {
        // Zombie "dim" is worth 1.5; 1.5 + max anomaly 2.0 < 4.0.
        let evidence = Fixtures.evidence { m, _ in m.brightness = 0.28 }
        for calibration in 0..<100 {
            #expect(VerdictEngine.decide(evidence, seed: Fixtures.seed(calibration)).monster == .human)
        }
    }

    @Test("Clue points at the threshold always produce a monster")
    func atThresholdIsMonster() {
        // Robot: serious 2 + blue shirt 2 = 4.0.
        let evidence = Fixtures.evidence { _, o in o.expression = .serious; o.shirtColor = "blue" }
        for calibration in 0..<100 {
            #expect(VerdictEngine.decide(evidence, seed: Fixtures.seed(calibration)).monster != .human)
        }
    }

    // MARK: Output shape

    @Test("Confidence stays within 51–99.9% and there are always 3 clues")
    func outputShape() {
        for (index, evidence) in Fixtures.random(count: 1_000).enumerated() {
            let verdict = VerdictEngine.decide(evidence, seed: Fixtures.seed(index))
            #expect((51...99.9).contains(verdict.confidence))
            #expect(verdict.clues.count == 3)
            #expect(verdict.clues.allSatisfy { $0.monster == verdict.monster })
            #expect(Set(verdict.clues.map(\.id)).count == 3)
            #expect(verdict.caseNumber.hasPrefix("K9-"))
            #expect((120..<1000).contains(verdict.trueAgeYears))
        }
    }

    @Test("Real clues come first, strongest first")
    func clueOrdering() throws {
        let verdict = VerdictEngine.decide(try #require(Fixtures.strong[.vampire]), seed: Fixtures.seed(3))
        let points = verdict.clues.map(\.points)
        #expect(points == points.sorted(by: >))
        #expect(verdict.clues.allSatisfy { !$0.isAnomaly })
    }

    @Test("Anomaly readings pad the list when few clues fire")
    func anomalyPadding() {
        // Kaiju size alone: 3.5 × ramp ≈ 3.5 at 0.5 area, + anomaly may or may not clear 4.
        let evidence = Fixtures.evidence { m, _ in m.faceAreaFraction = 0.6 }
        let verdicts = (0..<50).map { VerdictEngine.decide(evidence, seed: Fixtures.seed($0)) }
        let kaiju = verdicts.filter { $0.monster == .kaiju }
        #expect(!kaiju.isEmpty)
        for verdict in kaiju {
            #expect(verdict.clues.filter(\.isAnomaly).count == 2)
        }
    }

    @Test("No face offers a Ghost verdict")
    func invisibleSubject() {
        let verdict = VerdictEngine.invisibleSubject(seed: Fixtures.seed(7))
        #expect(verdict.monster == .ghost)
        #expect(verdict.clues.count == 3)
        #expect((90...99.9).contains(verdict.confidence))
    }

    // MARK: Kindness (DECISIONS.md S-2)

    @Test("Hair colour, eye colour and age never change any score")
    func bodyTraitsAreIgnored() {
        for evidence in Fixtures.random(count: 60) {
            let base = VerdictEngine.decide(evidence, seed: Fixtures.seed(0)).scores
            for hair in HairColor.allCases where hair != .hidden {
                for eye in EyeColor.allCases {
                    for age in AgeBand.allCases {
                        var changed = evidence
                        changed.observations.hairColor = evidence.observations.hairColor == .hidden ? .hidden : hair
                        changed.observations.eyeColor = eye
                        changed.observations.ageBand = age
                        #expect(VerdictEngine.decide(changed, seed: Fixtures.seed(0)).scores == base)
                    }
                }
            }
        }
    }

    @Test("A mask never changes any score")
    func maskIsIgnored() {
        for evidence in Fixtures.random(count: 300) {
            var without = evidence
            without.observations.accessories.removeAll { $0 == .mask }
            var with = without
            with.observations.accessories.append(.mask)
            #expect(
                VerdictEngine.decide(with, seed: Fixtures.seed(0)).scores
                    == VerdictEngine.decide(without, seed: Fixtures.seed(0)).scores
            )
        }
    }

    @Test("Verdict spread across random photos includes every outcome")
    func spread() {
        var counts: [Monster: Int] = [:]
        for (index, evidence) in Fixtures.random(count: 2_000).enumerated() {
            counts[VerdictEngine.decide(evidence, seed: Fixtures.seed(index)).monster, default: 0] += 1
        }
        for monster in Monster.allCases {
            #expect((counts[monster] ?? 0) > 0, "never reached \(monster)")
        }
    }
}
