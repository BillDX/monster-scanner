import Foundation

/// One piece of evidence behind a verdict, shown to the player so the logic
/// is visible (and funny).
public struct Clue: Sendable, Equatable, Codable, Identifiable {
    /// The rule that produced it, e.g. "vampire.night".
    public let id: String
    public let monster: Monster
    /// Noun phrase for dossiers: "a black shirt", "a 94% full moon".
    public let evidence: String
    /// One-line explanation for the clue list: "Moon 94% full. DANGER."
    public let quip: String
    /// Points added to the monster's score. 0 for anomaly readings.
    public let points: Double

    public init(id: String, monster: Monster, evidence: String, quip: String, points: Double) {
        self.id = id
        self.monster = monster
        self.evidence = evidence
        self.quip = quip
        self.points = points
    }

    /// Anomaly readings pad the list when fewer than three real clues fired.
    public var isAnomaly: Bool { points == 0 }
}

/// A scoring rule. Every rule must be about clothing, accessories, setting,
/// timing, pose/framing, the photo itself, or the phone — never body traits
/// (spec section 4.2, DECISIONS.md S-2).
struct ClueRule: Sendable {
    let id: String
    let monster: Monster
    let weight: Double
    /// 0 when the rule doesn't apply, otherwise 0...1.
    let strength: @Sendable (ScanEvidence) -> Double
    let evidence: @Sendable (ScanEvidence) -> String
    let quip: @Sendable (ScanEvidence) -> String

    func clue(for e: ScanEvidence) -> Clue? {
        let s = strength(e)
        guard s > 0 else { return nil }
        return Clue(id: id, monster: monster, evidence: evidence(e), quip: quip(e), points: weight * s)
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func pct(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func deg(_ degrees: Double) -> String {
        String(format: "%.1f°", degrees)
    }

    /// Linear ramp from `floor` at `from` up to 1 at `to`, 0 below `from`.
    static func ramp(_ x: Double, from: Double, to: Double, floor: Double = 0.7) -> Double {
        guard x >= from else { return 0 }
        guard to > from else { return 1 }
        return min(1, floor + (1 - floor) * (x - from) / (to - from))
    }

    /// "a" or "an" in front of a phrase: "an 80% full moon", "an orange shirt",
    /// "a 64% full moon", "a uniform".
    static func a(_ phrase: String) -> String {
        let lower = phrase.lowercased()
        guard let first = lower.first else { return phrase }
        let an: Bool
        if first.isNumber {
            let digits = lower.prefix { $0.isNumber }
            an = digits.hasPrefix("8") || digits == "11" || digits == "18"
        } else if "aeio".contains(first) {
            an = true
        } else if first == "u" {
            an = !["uni", "use", "usu", "uk"].contains { lower.hasPrefix($0) }
        } else {
            an = lower.hasPrefix("hour") || lower.hasPrefix("honest")
        }
        return (an ? "an " : "a ") + phrase
    }

    static func shirt(_ e: ScanEvidence) -> String {
        let name = e.observations.shirtColor.trimmingCharacters(in: .whitespaces).lowercased()
        return (name.isEmpty || name == "unknown") ? e.observations.shirtFamily.displayName : name
    }
}
