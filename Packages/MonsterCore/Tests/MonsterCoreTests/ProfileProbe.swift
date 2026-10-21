import Testing
@testable import MonsterCore

/// Bill rescanning himself: blue shirt, straight-on, indoors, afternoon.
enum Profiles {
    static func bill(_ i: Int) -> ScanEvidence {
        var rng = SeededRandom(seed: UInt64(i) &* 7919)
        return Fixtures.evidence { m, o in
            o.shirtColor = "navy blue"
            o.expression = [.serious, .smiling, .serious, .smiling, .unknown][Int(rng.next() % 5)]
            o.backgroundHint = "living room"
            o.accessories = []
            m.headRollDegrees = (rng.unit() - 0.5) * 3      // within ±1.5°
            m.headYawDegrees = (rng.unit() - 0.5) * 10
            m.faceAreaFraction = 0.12 + rng.unit() * 0.1
            m.faceCenterOffset = rng.unit() * 0.08
            m.brightness = 0.45 + rng.unit() * 0.15
            m.blurVariance = 500 + rng.unit() * 900
            m.minutesSinceMidnight = 15 * 60 + Int(rng.next() % 90)
            m.moonIllumination = 0.8
            m.batteryLevel = 0.7
        }
    }
}

@Suite("Rescanning the same outfit stays varied (D-027)")
struct ProfileProbe {
    @Test("Bill's blue shirt no longer means robot every time")
    func billSpread() {
        var counts: [Monster: Int] = [:]
        for i in 0..<1_000 {
            counts[VerdictEngine.decide(Profiles.bill(i), seed: Fixtures.seed(i, bytes: [UInt8(i % 251), 7])).monster, default: 0] += 1
        }
        print("BILL " + Monster.allCases.map { "\($0.rawValue) \((counts[$0] ?? 0) / 10)%" }.joined(separator: " · "))
        #expect((counts[.robot] ?? 0) <= 450, "robot \((counts[.robot] ?? 0) / 10)%")
        #expect(Monster.allCases.filter { (counts[$0] ?? 0) >= 20 }.count >= 6, "at least 6 verdicts turn up 2%+ of the time")
    }
}

@Suite("Reasoning samples (printed for review)")
struct ReasoningSamples {
    @Test func printSamples() {
        for i in 0..<8 {
            let evidence = Profiles.bill(i)
            let verdict = VerdictEngine.decide(evidence, seed: Fixtures.seed(i + 40))
            let steps = Reasoning.chain(for: verdict, evidence: evidence)
            print("REASONING [\(verdict.monster.rawValue)\(verdict.wildcard != nil ? " wild" : "")]\n  " + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n  "))
        }
    }
}
