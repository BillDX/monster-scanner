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

extension Fixtures {
    /// A believable mix of party photos: mostly level heads, lots of smiles,
    /// common shirt colours, glasses fairly common, mostly evenings indoors.
    /// Used to check that no verdict dominates in real use.
    static func realistic(count: Int, seed: UInt64 = 7, daytime: Bool = false) -> [ScanEvidence] {
        var rng = SeededRandom(seed: seed)
        func u() -> Double { rng.unit() }
        func weighted<T>(_ items: [(T, Double)]) -> T {
            let total = items.reduce(0) { $0 + $1.1 }
            var r = u() * total
            for (item, w) in items { r -= w; if r <= 0 { return item } }
            return items.last!.0
        }
        func normal() -> Double { // Box–Muller
            sqrt(-2 * log(max(1e-9, u()))) * cos(2 * .pi * u())
        }
        return (0..<count).map { _ in
            evidence { m, o in
                o.expression = daytime
                    ? weighted([(.smiling, 40), (.serious, 42), (.surprised, 5), (.sillyFace, 6), (.sleepy, 3), (.unknown, 4)])
                    : weighted([(.smiling, 45), (.serious, 30), (.surprised, 6), (.sillyFace, 8), (.sleepy, 4), (.unknown, 7)])
                o.shirtColor = weighted([("black", 20), ("white", 13), ("navy blue", 9), ("light blue", 5), ("gray", 11),
                                         ("red", 6), ("green", 5), ("brown", 4), ("beige", 4), ("pink", 4), ("yellow", 3),
                                         ("purple", 3), ("orange", 2), ("red plaid flannel", 2), ("unknown", 9)])
                var worn: [Accessory] = []
                if u() < 0.30 { worn.append(.glasses) }
                if u() < 0.04 { worn.append(.sunglasses) }
                if u() < 0.08 { worn.append(.hat) } else if u() < 0.04 { worn.append(.hood) }
                if u() < 0.04 { worn.append(.headphones) }
                if u() < 0.15 { worn.append(.earrings) }
                if u() < 0.10 { worn.append(.necklace) }
                if u() < 0.04 { worn.append(.scarf) }
                o.accessories = Array(worn.prefix(3))
                o.hairColor = worn.contains(.hat) || worn.contains(.hood) ? .hidden
                    : weighted([(.brown, 40), (.black, 30), (.blonde, 15), (.gray, 8), (.red, 4), (.dyedOther, 3)])
                o.backgroundHint = weighted([("living room", 40), ("kitchen", 15), ("bar", 10), ("party", 10),
                                             ("garden", 8), ("city street", 7), ("beach", 3), ("unknown", 7)])
                // Selfies are closer than group shots.
                m.faceAreaFraction = min(0.6, max(0.01, weighted([(0.04, 25), (0.08, 30), (0.14, 25), (0.22, 12), (0.32, 5), (0.42, 3)])
                                                  * (0.8 + 0.4 * u())))
                m.faceCenterOffset = abs(normal()) * 0.12
                m.headRollDegrees = normal() * (daytime ? 3.5 : 5)
                m.headYawDegrees = normal() * 12
                m.brightness = min(0.95, max(0.05, 0.42 + normal() * 0.13))
                m.blurVariance = exp(log(daytime ? 700 : 450) + normal() * 0.6) // daylight photos are sharper
                m.moonIllumination = u()
                // Party hours, with some daytime.
                let hour = daytime
                    ? weighted([(10, 10), (11, 15), (12, 20), (13, 20), (14, 15), (15, 10), (16, 10)])
                    : weighted([(12, 6), (15, 8), (17, 8), (19, 14), (20, 16), (21, 16), (22, 14), (23, 10), (0, 5), (1, 3)])
                m.minutesSinceMidnight = hour * 60 + Int(u() * 60)
                m.batteryLevel = u() < 0.1 ? 0.05 + u() * 0.14 : 0.2 + u() * 0.8
                m.shirtHueDegrees = nil
            }
        }
    }

    static func spread(_ evidence: [ScanEvidence]) -> [Monster: Double] {
        var counts: [Monster: Int] = [:]
        for (i, e) in evidence.enumerated() {
            counts[VerdictEngine.decide(e, seed: seed(i)).monster, default: 0] += 1
        }
        return counts.mapValues { Double($0) / Double(evidence.count) }
    }
}
