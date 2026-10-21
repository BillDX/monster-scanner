import Foundation

/// The kindness rules from spec section 5, as a word check. Every dossier
/// template, clue line and telemetry line is run through this in the tests,
/// so a banned word fails `swift test` / `xcodebuild test`. From M3 the same
/// check screens model-written dossiers before they are shown.
public enum ContentPolicy {
    public enum Topic: String, Sendable, CaseIterable {
        case appearance, bodyShape, ethnicity, health, ageMockery, violence, insult
    }

    public struct Violation: Sendable, Equatable, CustomStringConvertible {
        public let term: String
        public let topic: Topic
        public var description: String { "\"\(term)\" (\(topic.rawValue))" }
    }

    /// Whole-word, case-insensitive. A trailing `*` matches any ending
    /// ("wrinkl*" catches wrinkle, wrinkled, wrinkly).
    static let banned: [Topic: [String]] = [
        .appearance: [
            "skin", "complexion", "pale", "pasty", "ugly", "hideous", "attractive", "unattractive",
            "pretty", "handsome", "beautiful", "gorgeous", "sexy", "hottie", "cute", "wrinkl*", "bald*",
            "acne", "pimpl*", "freckl*", "teeth", "nose", "chin", "forehead", "ears", "lips",
        ],
        .bodyShape: [
            "fat", "fatty", "obese", "overweight", "underweight", "skinny", "scrawny", "chubby", "plump",
            "weight", "belly", "tummy", "body", "bodies", "curvy", "flabby", "lanky",
        ],
        .ethnicity: ["race", "racial", "ethnic*", "nationality", "foreign*", "exotic"],
        .health: [
            "disab*", "handicap*", "wheelchair", "blind", "deaf", "sick", "sickly", "ill", "illness",
            "disease*", "diagnos*", "medical", "medication", "virus", "infect*", "cancer", "diabet*",
            "autis*", "adhd", "depress*", "crazy", "insane", "psycho*", "mental*", "injur*",
        ],
        .ageMockery: ["elderly", "senile", "geriatric", "wrinkly", "over the hill"],
        .violence: [
            "blood*", "kill*", "murder*", "corpse*", "gore", "gory", "guts", "stab", "stabbed", "stabbing", "dead", "death", "die",
            "dies", "bite marks", "weapon*", "gun*",
        ],
        .insult: ["stupid", "idiot*", "dumb", "loser*", "freak*", "creep", "weirdo", "moron*", "lame"],
    ]

    private static let patterns: [(term: String, topic: Topic, regex: NSRegularExpression)] = {
        Topic.allCases.flatMap { topic in
            (banned[topic] ?? []).map { term in
                let core = NSRegularExpression.escapedPattern(for: term.replacingOccurrences(of: "*", with: ""))
                    .replacingOccurrences(of: " ", with: "\\s+")
                let pattern = term.hasSuffix("*") ? "\\b\(core)\\w*" : "\\b\(core)\\b"
                // swiftlint:disable:next force_try
                let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                return (term, topic, regex)
            }
        }
    }()

    public static func violations(in text: String) -> [Violation] {
        let range = NSRange(text.startIndex..., in: text)
        return patterns
            .filter { $0.regex.firstMatch(in: text, range: range) != nil }
            .map { Violation(term: $0.term, topic: $0.topic) }
    }

    public static func isAllowed(_ text: String) -> Bool {
        violations(in: text).isEmpty
    }
}
