import Foundation

/// The kindness rules from spec section 5, as a word check. Every dossier
/// template, clue line and telemetry line is run through this in the tests,
/// so a banned word fails `swift test` / `xcodebuild test`. From M3 the same
/// check screens model-written dossiers before they are shown.
public enum ContentPolicy {
    public enum Topic: String, Sendable, CaseIterable {
        case appearance, bodyShape, ethnicity, religion, health, ageMockery, violence, insult, negativity
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
            "skin", "skins", "skinned", "skintone", "skin-tone", "tanned", "beard*", "moustache*", "mustache*", "stubble", "hairline", "eyelash*",
            "makeup", "lipstick", "good-looking", "plain-looking",
        ],
        .bodyShape: [
            "fat", "fatty", "obese", "overweight", "underweight", "skinny", "scrawny", "chubby", "plump",
            "weight", "belly", "tummy", "body", "bodies", "curvy", "flabby", "lanky", "height", "petite",
            "stocky", "muscular", "buff",
        ],
        .ethnicity: [
            "race", "racial", "ethnic*", "nationality", "foreign*", "exotic", "asian", "african", "caucasian",
            "hispanic", "latino", "latina", "latinx", "arab*", "indigenous", "native", "european", "oriental",
        ],
        .religion: ["religio*", "muslim", "christian", "jewish", "hindu", "buddhist", "sikh", "hijab", "turban"],
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
        .insult: ["stupid", "idiot*", "dumb", "loser*", "freak*", "creep", "weirdo", "moron*", "lame", "ugh"],
    ]

    /// Extra words banned only in text the AI writes (strict mode). Our own
    /// game text may say the Bureau is "disappointed"; the model may not say
    /// anything unkind or age-related about a person.
    static let strictExtras: [Topic: [String]] = [
        .negativity: [
            "awkward", "weird", "messy", "sloppy", "dirty", "lazy", "boring", "annoying", "cringe*", "embarrass*",
            "sad", "upset", "crying", "miserable", "grumpy", "angry", "scowl*", "frown*", "disappoint*",
            "unflattering", "unfortunate", "tired-looking", "worn out", "scary-looking",
        ],
        .ageMockery: ["old", "older", "oldest", "aging", "ageing", "elder*", "youthful", "young-looking"],
        .appearance: ["looks", "looking good", "tone", "glamorous", "stunning", "hot"],
    ]

    /// Colour words are fine for clothes ("black hat") but never for people.
    static let peoplePatterns: [String] = [
        #"\b(black|white|brown|yellow|red|dark|light|pale|olive)[- ]?(person|people|man|men|woman|women|guy|guys|girl|girls|boy|boys|kid|kids|lady|ladies|folk|folks|skinned|complexion)\b"#,
    ]

    private typealias Pattern = (term: String, topic: Topic, regex: NSRegularExpression)

    private static func compile(_ list: [Topic: [String]]) -> [Pattern] {
        Topic.allCases.flatMap { topic in
            (list[topic] ?? []).map { term in
                let core = NSRegularExpression.escapedPattern(for: term.replacingOccurrences(of: "*", with: ""))
                    .replacingOccurrences(of: " ", with: "\\s+")
                let pattern = term.hasSuffix("*") ? "\\b\(core)\\w*" : "\\b\(core)\\b"
                // swiftlint:disable:next force_try
                let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                return (term, topic, regex)
            }
        }
    }

    private static let patterns: [Pattern] = {
        let people = peoplePatterns.map { pattern in
            // swiftlint:disable:next force_try
            (pattern, Topic.ethnicity, try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
        }
        return people + compile(banned)
    }()

    private static let strictPatterns: [Pattern] = patterns + compile(strictExtras)

    /// `strict: true` for anything the AI wrote.
    public static func violations(in text: String, strict: Bool = false) -> [Violation] {
        let range = NSRange(text.startIndex..., in: text)
        return (strict ? strictPatterns : patterns)
            .filter { $0.regex.firstMatch(in: text, range: range) != nil }
            .map { Violation(term: $0.term, topic: $0.topic) }
    }

    public static func isAllowed(_ text: String, strict: Bool = false) -> Bool {
        violations(in: text, strict: strict).isEmpty
    }
}
