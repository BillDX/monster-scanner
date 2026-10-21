import Foundation

/// Chaos Mode (spec section 4.2b): the AI scores every monster in the
/// observation call and picks the verdict; code only clamps the scores and
/// keeps the kindness rules. A deliberate experiment against the code verdict.
public enum ChaosMode {
    /// Observation prompt plus the scores request.
    public static let user = ObservationPrompt.user + """

    Also include "monster_scores": an object with an integer from 0 to 100 for each of \
    "vampire", "alien", "kaiju", "werewolf", "zombie", "robot" and "ghost": how much this person \
    seems like each monster in this silly game, judging only by clothing, accessories, pose, \
    expression and setting. Be bold and playful with the numbers.
    """

    public static let retryUser = user + "\nReturn only valid JSON."

    public static let maxTokens = ObservationPrompt.maxTokens + 60

    /// The observation grammar with `monster_scores` before the closing brace.
    public static let grammar: String = {
        let base = ObservationPrompt.grammar
        let scores = Monster.scorable.map { "\"\\\"\($0.rawValue)\\\":\" ws score" }.joined(separator: " \",\" ws ")
        return base
            .replacingOccurrences(
                of: "ws short ws \"}\"\n",
                with: "ws short \",\" ws \"\\\"monster_scores\\\":\" ws scores ws \"}\"\n"
            )
            + "\nscores ::= \"{\" ws \(scores) ws \"}\"\nscore ::= \"100\" | [1-9] [0-9] | [0-9]\n"
    }()

    /// Reads `monster_scores` from the model output; missing monsters count 0.
    public static func scores(from raw: String) -> [Monster: Int]? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scores = object["monster_scores"] as? [String: Any] else { return nil }
        var result: [Monster: Int] = [:]
        for monster in Monster.scorable {
            let value = (scores[monster.rawValue] as? NSNumber)?.intValue ?? 0
            result[monster] = min(100, max(0, value))
        }
        return result
    }

    /// Below this top score the AI is overruled into CERTIFIED HUMAN.
    public static let humanBelow = 40
}

extension VerdictEngine {
    /// Chaos verdict: the AI's highest (clamped) score wins. Clues are still
    /// written by code: the winning monster's real clues if any fired, padded
    /// with anomaly readings, so the evidence stays kind.
    public static func chaos(_ evidence: ScanEvidence, scores: [Monster: Int], seed: UInt64) -> Verdict {
        var rng = SeededRandom(seed: seed)
        let ranked = Monster.scorable
            .map { ($0, min(100, max(0, scores[$0] ?? 0))) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : Monster.scorable.firstIndex(of: $0.0)! < Monster.scorable.firstIndex(of: $1.0)! }
        let (best, top) = ranked[0]
        let runnerUp = ranked[1].1
        let trueAge = 120 + Int(rng.next() % 880)
        let caseNumber = String(format: "C4-%04d", Int(rng.next() % 10_000)) // C4 = chaos case
        let wobble = rng.unit() * 2.9
        let monsterScores = Monster.scorable.map {
            MonsterScore(monster: $0, cluePoints: Double(scores[$0] ?? 0) / 10, anomaly: 0)
        }

        guard top >= ChaosMode.humanBelow else {
            let confidence = clampConfidence(51 + Double(ChaosMode.humanBelow - top) * 1.1 + wobble)
            let nearMiss = MonsterScore(monster: best, cluePoints: Double(top) / 100 * humanThreshold, anomaly: 0)
            return Verdict(
                monster: .human, confidence: confidence, clues: humanClues(nearMiss: nearMiss, rng: &rng),
                scores: monsterScores, seed: seed, trueAgeYears: trueAge, caseNumber: caseNumber
            )
        }

        let confidence = clampConfidence(51 + Double(top) * 0.3 + Double(top - runnerUp) * 0.35 + wobble)
        let real = ClueBook.rules.filter { $0.monster == best }.compactMap { $0.clue(for: evidence) }
            .sorted { $0.points > $1.points }
        let clues = Array(real.prefix(3)) + anomalyClues(for: best, count: max(0, 3 - real.count), rng: &rng)
        return Verdict(
            monster: best, confidence: confidence, clues: clues,
            scores: monsterScores, seed: seed, trueAgeYears: trueAge, caseNumber: caseNumber
        )
    }
}
