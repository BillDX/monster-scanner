import Foundation

/// The AI dossier call (spec section 4.3, M3). The verdict and clues come
/// from code; the model only writes the words. Hair, eye colour and age are
/// left out on purpose (DECISIONS.md S-2).
public enum DossierPrompt {
    public static let system = """
    You are AGENT K-9, a dramatic but kind field agent of the Bureau of Secret Monster Affairs. \
    You write short, silly, affectionate, family-friendly spy-drama dossiers. You never insult anyone.
    """

    /// Builds the user message from the code's verdict and the observations.
    public static func user(for input: DossierInput, styleExample includeExample: Bool = false) -> String {
        let isHuman = input.monster == .human
        let verdict = isHuman ? "CERTIFIED HUMAN" : input.monster.rawValue.uppercased()
        var facts: [String] = []
        if let subspecies = input.subspecies { facts.append("subspecies: \(subspecies)") }
        facts.append("evidence: " + input.clueEvidence.prefix(3).joined(separator: "; "))
        if ColorFamily(name: input.shirtColor) != .unknown { facts.append("shirt: \(input.shirtColor)") }
        if !input.funDetails.isEmpty { facts.append("spotted: " + input.funDetails.joined(separator: "; ")) }
        if let read = input.expressionRead { facts.append("expression: \(read)") }
        if let setting = input.setting, setting != "unknown" { facts.append("setting: \(setting)") }
        if let vibe = input.vibe { facts.append("agent's hunch: \(vibe)") }

        let premise = isHuman
            ? "Write a classified dossier revealing that, after a thorough scan, the subject is a CERTIFIED HUMAN. " +
              "The joke is that the Bureau is comically let down that no monster turned up; the joke is never on the subject."
            : "Write a classified dossier revealing that the subject is a \(verdict)."
        return """
        \(premise)
        Case facts (weave two or three into the story; do not list them):
        \(facts.map { "- " + $0 }.joined(separator: "\n"))
        \(includeExample ? "Style example from a different case (write a NEW dossier in this spirit; do not copy its sentences):\n" + styleExample(for: input) + "\n" : "")Rules:
        - 3 to 5 short sentences, at most 100 words, plain text, one paragraph.
        - Over-the-top spy drama, silly fantasy and wordplay are welcome. Be warm and affectionate; teasing is not.
        - The verdict is final: the subject is a \(verdict).\(isHuman ? "" : " Do not suggest any other monster.")
        - Only joke about clothing, accessories, objects, pose, expression, setting, timing and the evidence.
        - Never mention skin or skin colour, race, ethnicity, nationality, religion, body, height, weight, \
        looks, health, disabilities, hair or facial hair. Never guess names.
        Then on a new line write "Recommended action:" followed by one harmless, funny suggestion.
        """
    }

    /// One of our hand-written templates for this verdict, filled with neutral
    /// example evidence, as a style guide for the 2B model.
    static func styleExample(for input: DossierInput) -> String {
        let templates = DossierLibrary.bundled.templates[input.monster] ?? []
        guard !templates.isEmpty else { return "" }
        // Not the template the fallback would show for this seed.
        let template = templates[Int(((input.seed >> 17) + 3) % UInt64(templates.count))]
        let example = DossierInput(
            monster: input.monster,
            clueEvidence: ["a striped umbrella", "a photo taken at 20:15", "a suspiciously tidy desk"],
            shirtColor: "yellow", confidenceText: "77.0%", caseNumber: "K9-0000", trueAgeYears: 333, seed: 0
        )
        let dossier = DossierLibrary.render(template, with: example)
        return dossier.body + "\nRecommended action: " + dossier.recommendedAction
    }

    public static let maxTokens = 200

    // MARK: Field notes (the M3 design, D-022): the hand-written template stays
    // the dossier; the model adds a short, personal postscript.

    /// On-theme comedy hooks so a small model stays on-topic.
    public static let jokeAngles: [Monster: String] = [
        .vampire: "capes, avoiding sunlight, garlic, mirrors, dramatic entrances, midnight snacks, tomato juice",
        .alien: "the mothership, antennae, studying Earth snacks, 'take me to your leader', crop circles, beeping signals",
        .kaiju: "stomping tiny cities, mighty roars, naps in the harbour, eating an entire buffet, being enormous but gentle",
        .werewolf: "full moons, howling, playing fetch, frisbees, tennis balls, zoomies, guarding the snack table",
        .zombie: "slow shuffling, needing coffee, brunch instead of brains, naps, slippers, groaning at alarm clocks",
        .robot: "beeps and boops, batteries, firmware updates, spreadsheets, Wi-Fi, perfect tidiness, winning at chess",
        .ghost: "floating, bedsheets, creaky doors, saying boo, cold spots, appearing in the background of photos",
        .human: "the Bureau being comically let down, suspiciously ordinary hobbies like paying bills and eating salad",
    ]

    public static func fieldNotesUser(for input: DossierInput) -> String {
        let isHuman = input.monster == .human
        var seen: [String] = input.funDetails
        if ColorFamily(name: input.shirtColor) != .unknown { seen.append("\(input.shirtColor) shirt") }
        if seen.count < 2 { seen += input.clueEvidence.prefix(2 - seen.count) }
        let proof = isHuman
            ? "funny reason it proves they are, sadly for the Bureau, just a nice normal human"
            : "funny reason it proves they are secretly a \(input.monster.rawValue)"
        return """
        Subject: \(isHuman ? "a CERTIFIED HUMAN" : "a " + input.monster.rawValue). In the photo: \(seen.joined(separator: ", ")).
        Pick two of those things. For each, write one line in this form: "That [thing]? [\(proof)]."
        Ideas: \(jokeAngles[input.monster] ?? "").
        Keep it kind and silly. Never comment on the person's body, skin, looks, age or hair.
        """
    }

    public static let fieldNotesMaxTokens = 90

    /// Full-dossier settings (tried in M3, not used by the app; see D-022).
    public static let temperature: Float = 0.7
    public static let repeatPenalty: Float = 1.18

    /// 3 to 5 plain sentences, then the recommended action. A "." is only a
    /// sentence end, except between digits ("87.3%").
    public static let grammar = """
    root ::= sentence (" " sentence){2,4} "\\n\\nRecommended action: " action
    sentence ::= [A-Z] piece{8,220} [.!?]
    action ::= [A-Z] piece{4,140} [.!]
    piece ::= [a-zA-Z0-9 ,';:%()-] | [0-9] "." [0-9]
    """

    /// Exactly two "That [thing]? [reason]." lines.
    public static let fieldNotesGrammar = """
    root ::= line " " line
    line ::= "That " thing "? " [A-Z] piece{10,150} [.!]
    thing ::= [a-zA-Z ,'-]{2,40}
    piece ::= [a-zA-Z0-9 ,';:%()-] | [0-9] "." [0-9]
    """
}

/// Turns the streamed text into checked sentences (spec section 5). Each
/// sentence is held until complete, then passed only if it clears the strict
/// kindness check and doesn't name a different monster than the verdict.
public struct DossierStreamFilter: Sendable {
    public let verdict: Monster
    public private(set) var acceptedSentences: [String] = []
    public private(set) var rejectedSentences: [String] = []
    public private(set) var recommendedAction: String?
    private var buffer = ""
    private var inAction = false

    public static let maxWords = 120
    static let marker = "Recommended action:"

    public init(verdict: Monster) {
        self.verdict = verdict
    }

    /// Feed a streamed piece; returns sentences that became visible.
    public mutating func feed(_ piece: String) -> [String] {
        buffer += piece
        var released: [String] = []
        if !inAction, let range = buffer.range(of: Self.marker) {
            let before = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            inAction = true
            released += takeSentences(from: before, flushAll: true)
        }
        if !inAction {
            let (sentences, rest) = Self.split(buffer)
            buffer = rest
            for sentence in sentences { if let ok = accept(sentence) { released.append(ok) } }
        }
        return released
    }

    /// Call at the end of the stream.
    public mutating func finish() -> [String] {
        var released: [String] = []
        if inAction {
            let action = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !action.isEmpty, ContentPolicy.isAllowed(action, strict: true), !mentionsOtherMonster(action),
               action.split(separator: " ").count <= 25 {
                recommendedAction = action
            }
        } else {
            released += takeSentences(from: buffer, flushAll: true)
        }
        buffer = ""
        return released
    }

    public var body: String { acceptedSentences.joined(separator: " ") }

    /// True when enough survived to replace the template.
    public var isUsable: Bool { acceptedSentences.count >= 2 && recommendedAction != nil }

    public func dossier() -> Dossier? {
        guard isUsable, let recommendedAction else { return nil }
        return Dossier(body: body, recommendedAction: recommendedAction)
    }

    // MARK: Internals

    private mutating func takeSentences(from text: String, flushAll: Bool) -> [String] {
        var (sentences, rest) = Self.split(text)
        if flushAll {
            let tail = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { sentences.append(tail) }
            rest = ""
        }
        return sentences.compactMap { accept($0) }
    }

    private mutating func accept(_ raw: String) -> String? {
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentence.count >= 3 else { return nil }
        let words = acceptedSentences.joined(separator: " ").split(separator: " ").count
        guard words + sentence.split(separator: " ").count <= Self.maxWords,
              ContentPolicy.isAllowed(Self.maskingTrueAge(sentence), strict: true),
              !Self.isEcho(sentence),
              !mentionsOtherMonster(sentence) else {
            rejectedSentences.append(sentence)
            return nil
        }
        acceptedSentences.append(sentence)
        return sentence
    }

    /// The "true age: 412 years" joke may say "412-year-old"; that's the game's
    /// joke, not a remark about the person, so it's masked before the age check.
    public static func maskingTrueAge(_ text: String) -> String {
        text.replacingOccurrences(of: #"\b\d{2,4}[- ]years?[- ]old\b"#, with: "ancient", options: .regularExpression)
    }

    public var isFull: Bool { body.split(separator: " ").count >= Self.maxWords - 8 }

    /// Small models sometimes repeat the instructions back; those lines go.
    static let echoPhrases = [
        "field notes", "joke ideas", "try ideas", "sentences", "teasing", "connecting what", "be warm",
        "never mention", "never comment", "only joke", "keep it kind", "agent k-9 explains", "in the photo:",
        "subject:", "the scanner has identified", "recommended action",
    ]

    static func isEcho(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return echoPhrases.contains { lower.contains($0) }
    }

    private func mentionsOtherMonster(_ text: String) -> Bool {
        let lower = text.lowercased()
        // A human dossier may mention the near miss ("not a ghost after all").
        if verdict == .human {
            let negations = ["not", "no", "almost", "nearly", "near-miss", "never", "isn't", "wasn't", "ruled out", "zero"]
            if negations.contains(where: { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) { return false }
        }
        let others = Monster.scorable.filter { $0 != verdict }
        return others.contains { monster in
            let names = [monster.rawValue, monster.rawValue + "s"] + (monster == .zombie ? ["undead"] : [])
            return names.contains { name in
                lower.range(of: "\\b\(name)\\b", options: .regularExpression) != nil
            }
        }
    }

    /// Splits complete sentences (ending . ! or ? followed by space or end).
    static func split(_ text: String) -> (sentences: [String], rest: String) {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let c = characters[index]
            current.append(c)
            if ".!?".contains(c) {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // Only a boundary when followed by whitespace (not "3.5" or "K-9.").
                if let next, next == " " || next == "\n" {
                    sentences.append(current)
                    current = ""
                }
            }
            index += 1
        }
        return (sentences, current)
    }
}
