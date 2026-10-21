import Foundation
@testable import MonsterCore

/// Evidence builders shared by the tests.
enum Fixtures {
    /// Nothing interesting: no rule fires.
    static let neutral = ScanEvidence(measurements: Measurements(), observations: .unknown)

    static func evidence(
        _ configure: (inout Measurements, inout SubjectObservations) -> Void
    ) -> ScanEvidence {
        var m = Measurements()
        var o = SubjectObservations.unknown
        configure(&m, &o)
        return ScanEvidence(measurements: m, observations: o)
    }

    /// One strongly-matching photo per verdict.
    static let strong: [Monster: ScanEvidence] = [
        .vampire: evidence { m, o in
            o.shirtColor = "black"; o.accessories = [.sunglasses]; o.backgroundHint = "living room"
            m.minutesSinceMidnight = 23 * 60 + 41; m.batteryLevel = 0.1; m.brightness = 0.18
        },
        .alien: evidence { m, o in
            o.shirtColor = "lime green"; o.expression = .surprised; o.accessories = [.glasses]
            m.headRollDegrees = -20; m.faceCenterOffset = 0.02
        },
        .kaiju: evidence { m, o in
            o.shirtColor = "charcoal"; o.expression = .sillyFace; o.backgroundHint = "city park"
            m.faceAreaFraction = 0.45
        },
        .werewolf: evidence { m, o in
            o.shirtColor = "red plaid flannel"; o.accessories = [.hood]; o.hairColor = .hidden
            o.backgroundHint = "forest trail"
            m.moonIllumination = 0.97; m.minutesSinceMidnight = 20 * 60 + 15
        },
        .zombie: evidence { m, o in
            o.shirtColor = "beige"; o.expression = .sleepy
            m.minutesSinceMidnight = 6 * 60 + 5; m.brightness = 0.25; m.headRollDegrees = 9; m.headYawDegrees = 30
        },
        .robot: evidence { m, o in
            o.shirtColor = "navy blue"; o.expression = .serious; o.accessories = [.headphones, .earrings]
            m.headRollDegrees = 0.8; m.blurVariance = 1500
        },
        .ghost: evidence { m, o in
            o.shirtColor = "white"
            m.brightness = 0.9; m.blurVariance = 30; m.faceAreaFraction = 0.02; m.minutesSinceMidnight = 60 + 13
        },
        .human: neutral,
    ]

    static func seed(_ calibration: Int, bytes: [UInt8] = [1, 2, 3, 4]) -> UInt64 {
        SeededRandom.seed(imageBytes: bytes, calibration: calibration)
    }

    /// Reproducible random evidence for property-style tests.
    static func random(count: Int, seed: UInt64 = 42) -> [ScanEvidence] {
        var rng = SeededRandom(seed: seed)
        func pick<T>(_ items: [T]) -> T { items[Int(rng.next() % UInt64(items.count))] }
        let shirts = ColorFamily.allCases.map(\.rawValue) + ["red plaid", "navy blue", "olive", "unknown"]
        let hints = ["city park", "kitchen", "beach at sunset", "office", "unknown", "forest trail", "bedroom"]
        return (0..<count).map { _ in
            evidence { m, o in
                o.shirtColor = pick(shirts)
                o.expression = pick(FaceExpression.allCases)
                o.hairColor = pick(HairColor.allCases)
                o.eyeColor = pick(EyeColor.allCases)
                o.ageBand = pick(AgeBand.allCases)
                o.accessories = [pick(Accessory.allCases), pick(Accessory.allCases)]
                o.backgroundHint = pick(hints)
                m.faceCount = pick([1, 1, 2, 4])
                m.faceAreaFraction = pick([0.01, 0.05, 0.12, 0.25, 0.4, 0.6])
                m.faceCenterOffset = pick([0.01, 0.1, 0.3])
                m.headRollDegrees = pick([-25, -9, 0.5, 4, 15])
                m.headYawDegrees = pick([-40, 0, 10, 35])
                m.brightness = pick([0.05, 0.2, 0.28, 0.5, 0.9])
                m.blurVariance = pick([10, 59, 300, 1200])
                m.moonIllumination = pick([0.0, 0.5, 0.86, 1.0])
                m.minutesSinceMidnight = pick([0, 95, 330, 420, 720, 1100, 1300, 1439])
                m.batteryLevel = pick([nil, 0.05, 0.19, 0.5, 1.0])
                m.shirtHueDegrees = pick([nil, 12, 212])
            }
        }
    }
}
