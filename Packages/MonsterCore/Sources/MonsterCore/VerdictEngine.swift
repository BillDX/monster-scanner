import Foundation

public struct MonsterScore: Sendable, Equatable, Codable {
    public let monster: Monster
    /// Sum of clue points.
    public let cluePoints: Double
    /// Seeded random "anomaly factor".
    public let anomaly: Double
    /// Wild-card boost (0 unless this monster got the inexplicable reading).
    public var wildcard: Double = 0

    public var total: Double { cluePoints + anomaly + wildcard }
}

public struct Verdict: Sendable, Equatable, Codable {
    public let monster: Monster
    /// 51.0 ... 99.9, one decimal place.
    public let confidence: Double
    /// Exactly three clues, strongest first.
    public let clues: [Clue]
    /// Scores for every scorable monster, in `Monster.scorable` order.
    public let scores: [MonsterScore]
    /// The seed this verdict came from. Also drives dossier choice.
    public let seed: UInt64
    /// "True age: 412 years" joke for the readout.
    public let trueAgeYears: Int
    /// "K9-4821"
    public let caseNumber: String
    /// Set when an inexplicable "wild card" reading boosted a monster (D-027).
    public var wildcard: Monster? = nil

    /// "87.3%"
    public var confidenceText: String { String(format: "%.1f%%", confidence) }
}

/// Picks the verdict. Pure, deterministic and seeded: the same evidence and
/// seed always give the same verdict (spec section 4.2).
public enum VerdictEngine {
    /// The engine's knobs, grouped so the tests can compare settings (D-027).
    public struct Tuning: Sendable {
        public var humanThreshold: Double
        public var maxAnomaly: Double
        public var wildcardChance: Double
        public var wildcardBoost: Double
        /// Clue points are squashed toward this ceiling (diminishing returns),
        /// so piling up ordinary clues can't lock in one verdict. 0 = off.
        public var evidenceCeiling: Double

        public func effective(_ points: Double) -> Double {
            evidenceCeiling > 0 ? evidenceCeiling * (1 - exp(-points / evidenceCeiling)) : points
        }
    }

    /// If no monster's total reaches this, the subject is CERTIFIED HUMAN.
    public static let humanThreshold = 3.8
    /// Anomaly factor range added to each monster's score. Big enough to
    /// flip close calls and keep rescans of the same outfit varied (D-027).
    public static let maxAnomaly = 3.0
    /// Chance (per seed) of an inexplicable reading that boosts a random monster.
    public static let wildcardChance = 0.35
    public static let wildcardBoost = 3.0
    /// Diminishing returns: clue points p count as 4·(1 − e^(−p/4)), so
    /// a pile of ordinary clues (blue shirt + level head + neutral face) can't
    /// lock in one verdict for someone rescanning the same outfit (D-027).
    public static let evidenceCeiling = 4.0

    public static let standard = Tuning(
        humanThreshold: humanThreshold, maxAnomaly: maxAnomaly, wildcardChance: wildcardChance,
        wildcardBoost: wildcardBoost, evidenceCeiling: evidenceCeiling
    )

    public static func decide(_ evidence: ScanEvidence, seed: UInt64) -> Verdict {
        decide(evidence, seed: seed, tuning: standard)
    }

    public static func decide(_ evidence: ScanEvidence, seed: UInt64, tuning: Tuning) -> Verdict {
        var rng = SeededRandom(seed: seed)

        // 1. Score every monster. Fixed iteration order keeps this deterministic.
        var cluesByMonster: [Monster: [Clue]] = [:]
        for rule in ClueBook.rules {
            if let clue = rule.clue(for: evidence) {
                cluesByMonster[rule.monster, default: []].append(clue)
            }
        }
        var scores = Monster.scorable.map { monster in
            MonsterScore(
                monster: monster,
                cluePoints: tuning.effective((cluesByMonster[monster] ?? []).reduce(0) { $0 + $1.points }),
                anomaly: rng.unit() * tuning.maxAnomaly
            )
        }
        // The wild card: now and then the scanner just has a feeling.
        var wild: Monster?
        if rng.unit() < tuning.wildcardChance {
            let index = Int(rng.next() % UInt64(scores.count))
            scores[index].wildcard = tuning.wildcardBoost
            wild = scores[index].monster
        }

        // 2. Highest total wins; ties go to the earlier monster in the list.
        let ranked = scores.enumerated()
            .sorted { $0.element.total != $1.element.total ? $0.element.total > $1.element.total : $0.offset < $1.offset }
            .map(\.element)
        let best = ranked[0]
        let runnerUp = ranked[1]

        let trueAge = 120 + Int(rng.next() % 880)
        let caseNumber = String(format: "K9-%04d", Int(rng.next() % 10_000))

        // A small seeded wobble so "Second Opinion" always moves the number.
        let wobble = rng.unit() * 2.9

        // 3. Human if nothing cleared the threshold.
        guard best.total >= tuning.humanThreshold else {
            let confidence = clampConfidence(51 + 46 * (1 - best.total / tuning.humanThreshold) + wobble)
            return Verdict(
                monster: .human, confidence: confidence,
                clues: humanClues(nearMiss: best, rng: &rng),
                scores: scores, seed: seed, trueAgeYears: trueAge, caseNumber: caseNumber
            )
        }

        // 4. Confidence grows with the lead over the runner-up and the raw score.
        let margin = (best.total - runnerUp.total) + 0.25 * best.total
        let confidence = clampConfidence(51 + 46 * (1 - exp(-margin / 3)) + wobble)

        let real = (cluesByMonster[best.monster] ?? [])
            .enumerated()
            .sorted { $0.element.points != $1.element.points ? $0.element.points > $1.element.points : $0.offset < $1.offset }
            .map(\.element)
        let clues = Array(real.prefix(3)) + anomalyClues(for: best.monster, count: max(0, 3 - real.count), rng: &rng)

        return Verdict(
            monster: best.monster, confidence: confidence, clues: clues,
            scores: scores, seed: seed, trueAgeYears: trueAge, caseNumber: caseNumber,
            wildcard: wild == best.monster ? wild : nil
        )
    }

    /// No face was found: the scanner offers a Ghost verdict.
    public static func invisibleSubject(seed: UInt64) -> Verdict {
        var rng = SeededRandom(seed: seed)
        let confidence = clampConfidence(90 + rng.unit() * 9.9)
        let trueAge = 120 + Int(rng.next() % 880)
        let caseNumber = String(format: "K9-%04d", Int(rng.next() % 10_000))
        let clues = [
            Clue(
                id: "ghost.invisible", monster: .ghost,
                evidence: "a completely invisible subject",
                quip: "No subject detected. Are they… invisible?", points: 5
            ),
        ] + anomalyClues(for: .ghost, count: 2, rng: &rng)
        let scores = Monster.scorable.map {
            MonsterScore(monster: $0, cluePoints: $0 == .ghost ? 5 : 0, anomaly: 0)
        }
        return Verdict(
            monster: .ghost, confidence: confidence, clues: clues,
            scores: scores, seed: seed, trueAgeYears: trueAge, caseNumber: caseNumber
        )
    }

    // MARK: - Helpers

    static func clampConfidence(_ value: Double) -> Double {
        (min(99.9, max(51, value)) * 10).rounded() / 10
    }

    static func anomalyClues(for monster: Monster, count: Int, rng: inout SeededRandom) -> [Clue] {
        guard count > 0, var pool = ClueBook.anomalies[monster] else { return [] }
        var picked: [Clue] = []
        for _ in 0..<min(count, pool.count) {
            let index = Int(rng.next() % UInt64(pool.count))
            let item = pool.remove(at: index)
            picked.append(Clue(
                id: "\(monster.rawValue).anomaly.\(picked.count)", monster: monster,
                evidence: item.evidence, quip: item.quip, points: 0
            ))
        }
        return picked
    }

    static func humanClues(nearMiss: MonsterScore, rng: inout SeededRandom) -> [Clue] {
        var pool = ClueBook.humanReasons
        var clues: [Clue] = []
        if nearMiss.total > 0 {
            let share = Fmt.pct(nearMiss.total / humanThreshold)
            clues.append(Clue(
                id: "human.nearmiss", monster: .human,
                evidence: "a near-miss \(nearMiss.monster.rawValue) reading",
                quip: "Closest match: \(nearMiss.monster.rawValue.uppercased()) at \(share) of the alarm threshold.",
                points: 0
            ))
        }
        while clues.count < 3 && !pool.isEmpty {
            let item = pool.remove(at: Int(rng.next() % UInt64(pool.count)))
            clues.append(Clue(id: "human.\(clues.count)", monster: .human, evidence: item.evidence, quip: item.quip, points: 0))
        }
        return clues
    }
}
